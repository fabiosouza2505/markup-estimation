function [params, diagnostics] = estimate_translog_gmm_acf(data, config)
%ESTIMATE_TRANSLOG_GMM_ACF Two-step GMM não-linear ACF
%
% Implementa o estimador de Ackerberg, Caves & Frazer (2015) em dois
% passos (Hansen, 1982):
%
%   PASSO 1 (W = I):  β̂₁ = argmin g(β)'·g(β)
%   Construção de Ŵ:  Ŵ = [(1/N) Σ (Z·ξ̂)(Z·ξ̂)']⁻¹
%   PASSO 2 (W = Ŵ):  β̂₂ = argmin g(β)'·Ŵ·g(β)
%
% O segundo passo é assintoticamente eficiente (Hansen, 1982) e resolve
% o problema de identificação fraca do capital observado com W = I,
% pois Ŵ pondera os momentos pela inversa de sua variância, amplificando
% sinais informativos (capital) e atenuando ruído.
%
% ARQUITETURA:
%   1. precompute_lags: índices e matriz Z pré-computados (uma vez)
%   2. objective_gmm_fast: Q(β) vetorial com sigmoid bounds e W opcional
%   3. Multi-start Nelder-Mead com refinamento (ambos os passos)
%
% INPUTS:
%   data    - Tabela com: log_q, log_v, log_k, empresa, ano, (trimestre)
%   config  - Struct com campos opcionais:
%               markov_degree  : grau Markov (default: 3)
%               n_lags         : lags temporais (default: 5)
%               max_iter       : iterações por start (default: 5000)
%               tol_fun        : tolerância Q(β) (default: 1e-10)
%               tol_x          : tolerância parâmetros (default: 1e-10)
%               n_starts       : pontos iniciais (default: 20)
%               n_starts_step2 : pontos iniciais passo 2 (default: 10)
%               verbose        : progresso (default: true)
%               seed_from_ols  : OLS como seed #1 (default: true)
%               beta_2sls      : [β_v,β_k,β_vv,β_kk,β_vk] seed 2SLS
%               bounds         : struct .lb .ub (1×5)
%               two_step       : habilitar segundo passo (default: true)
%
% OUTPUTS:
%   params      - Struct com coeficientes estimados (do melhor passo)
%   diagnostics - Struct com diagnósticos completos de ambos os passos
%
% REFERÊNCIAS:
%   Ackerberg, Caves, & Frazer (2015), Econometrica, 83(6), 2411-2451.
%   Hansen (1982), Econometrica, 50(4), 1029-1054.
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

% =========================================================================
% 1. CONFIGURAÇÃO
% =========================================================================

if nargin < 2 || isempty(config)
    config = struct();
end

if ~isfield(config, 'markov_degree'), config.markov_degree = 3;      end
if ~isfield(config, 'n_lags'),        config.n_lags        = 5;      end
if ~isfield(config, 'max_iter'),      config.max_iter      = 5000;   end
if ~isfield(config, 'tol_fun'),       config.tol_fun       = 1e-10;  end
if ~isfield(config, 'tol_x'),         config.tol_x         = 1e-10;  end
if ~isfield(config, 'n_starts'),      config.n_starts      = 20;     end
if ~isfield(config, 'n_starts_step2'),config.n_starts_step2 = 10;    end
if ~isfield(config, 'verbose'),       config.verbose       = true;   end
if ~isfield(config, 'seed_from_ols'), config.seed_from_ols = true;   end
if ~isfield(config, 'beta_2sls'),     config.beta_2sls     = [];     end
if ~isfield(config, 'two_step'),      config.two_step      = true;   end

% Bounds econômicos default
% Bounds econômicos para Translog
% Nota: Na Translog, a elasticidade total do insumo j é:
%   ε_j = β_j + 2·β_jj·x̄_j + β_vk·x̄_other
% Portanto β_k ou β_v podem ser negativos se os termos quadráticos
% e de interação compensam. Os bounds devem ser amplos o suficiente
% para acomodar a parametrização Translog completa.
if ~isfield(config, 'bounds') || isempty(config.bounds)
    config.bounds.lb = [-1.50, -1.50, -0.50, -0.50, -0.50];
    config.bounds.ub = [ 2.00,  2.00,  0.50,  0.50,  0.50];
end
bounds = config.bounds;

if config.verbose
    fprintf('========================================\n');
    if config.two_step
        fprintf('GMM-ACF Two-Step (Hansen, 1982)\n');
    else
        fprintf('GMM-ACF (W = I)\n');
    end
    fprintf('========================================\n');
    fprintf('Bounds: β_v∈[%.2f,%.2f] β_k∈[%.2f,%.2f] quad∈[%.2f,%.2f]\n', ...
        bounds.lb(1), bounds.ub(1), bounds.lb(2), bounds.ub(2), ...
        bounds.lb(3), bounds.ub(3));
end

% =========================================================================
% 2. VALIDAÇÃO DOS DADOS
% =========================================================================

required_vars = {'log_q', 'log_v', 'log_k', 'empresa', 'ano'};
for i = 1:length(required_vars)
    if ~ismember(required_vars{i}, data.Properties.VariableNames)
        error('estimate_translog_gmm_acf: variável ''%s'' não encontrada.', required_vars{i});
    end
end

data = sortrows(data, {'empresa', 'ano'});
n_obs = height(data);

if config.verbose
    fprintf('1. Dados: %d observações\n', n_obs);
end

% =========================================================================
% 3. PRÉ-COMPUTAÇÃO DE LAGS E INSTRUMENTOS
% =========================================================================

if config.verbose
    fprintf('2. Pré-computando lags e instrumentos...\n');
    tic_pre = tic;
end

precomp = precompute_lags(data, config.n_lags);

if config.verbose
    fprintf('   Concluído em %.2f s | Markov: %d obs | Momentos: %d obs | M=%d\n', ...
        toc(tic_pre), precomp.n_valid_markov, precomp.n_valid_moments, precomp.n_moments);
end

% =========================================================================
% 4. FUNÇÕES DE TRANSFORMAÇÃO β ↔ θ
% =========================================================================

beta2theta = @(beta) log((beta - bounds.lb) ./ (bounds.ub - beta));
theta2beta = @(theta) bounds.lb + (bounds.ub - bounds.lb) ./ (1 + exp(-theta));
clip_beta  = @(beta) min(max(beta, bounds.lb + 1e-6), bounds.ub - 1e-6);

% =========================================================================
% 5. PONTOS INICIAIS
% =========================================================================

n_starts = config.n_starts;

if config.seed_from_ols
    log_q = data.log_q; log_v = data.log_v; log_k = data.log_k;
    X_cd    = [ones(n_obs,1), log_v, log_k];
    coef_cd = X_cd \ log_q;
    seed_v = coef_cd(2);  seed_k = coef_cd(3);
else
    seed_v = 0.5;  seed_k = 0.3;
end

rng(42, 'twister');
starts_beta = zeros(n_starts, 5);
starts_beta(1, :) = [seed_v, seed_k, 0.01, 0.01, 0.01];

s_next = 2;
if ~isempty(config.beta_2sls) && numel(config.beta_2sls) == 5
    starts_beta(2, :) = config.beta_2sls;
    s_next = 3;
    if config.verbose
        fprintf('3. Seeds: OLS (β_v=%.3f,β_k=%.3f) + 2SLS (β_v=%.3f,β_k=%.3f)\n', ...
            seed_v, seed_k, config.beta_2sls(1), config.beta_2sls(2));
    end
else
    if config.verbose
        fprintf('3. Seed OLS: β_v=%.4f | β_k=%.4f\n', seed_v, seed_k);
    end
end

n_perturb = ceil(n_starts / 2) - s_next + 1;
for s = s_next:(s_next + n_perturb - 1)
    if s > n_starts, break; end
    starts_beta(s, :) = [seed_v + 0.15*randn(), seed_k + 0.10*randn(), ...
                         0.02*randn(), 0.02*randn(), 0.02*randn()];
end
for s = (s_next + n_perturb):n_starts
    starts_beta(s, :) = bounds.lb + (bounds.ub - bounds.lb) .* rand(1,5);
end

starts_theta = zeros(n_starts, 5);
for s = 1:n_starts
    starts_theta(s, :) = beta2theta(clip_beta(starts_beta(s, :)));
end

% =========================================================================
% 6. PASSO 1: W = I (identidade)
% =========================================================================

if config.verbose
    fprintf('\n── PASSO 1: W = I ──────────────────────\n');
end

p_markov = config.markov_degree;
[beta_step1, fval_step1, all_results_s1, elapsed_s1] = ...
    run_multistart(obj_fun_factory(precomp, p_markov, bounds, []), ...
                   starts_theta, config, theta2beta);

if config.verbose
    beta_s1 = theta2beta(beta_step1);
    fprintf('   Passo 1 concluído em %.1f s\n', elapsed_s1);
    fprintf('   β₁ = [%.4f, %.4f, %.4f, %.4f, %.4f] | Q₁ = %.6e\n', ...
        beta_s1(1), beta_s1(2), beta_s1(3), beta_s1(4), beta_s1(5), fval_step1);
end

% =========================================================================
% 7. CONSTRUÇÃO DA MATRIZ DE PONDERAÇÃO ÓTIMA Ŵ
%
% Ŵ = Ω̂⁻¹  onde  Ω̂ = (1/N) Σᵢ (Zᵢ·ξ̂ᵢ)(Zᵢ·ξ̂ᵢ)'
%
% Ω̂ é o estimador HAC (Heteroskedasticity-consistent) da variância
% das condições de momento. Para robustez numérica, adicionamos
% regularização diagonal se Ω̂ estiver mal-condicionada.
% =========================================================================

beta_s1 = theta2beta(beta_step1);

if config.two_step
    if config.verbose
        fprintf('\n── CONSTRUINDO Ŵ ──────────────────────\n');
    end
    
    % ── Escolha do β para construção de Ω̂ ──
    % A qualidade de Ŵ depende criticamente da qualidade de ξ̂ usado
    % para construí-la. Se o passo 1 (W=I) produziu β com β_k no bound
    % (identificação fraca), os ξ̂ estão contaminados e Ŵ amplifica ruído.
    %
    % Estratégia: usar os betas do 2SLS (estimador consistente) quando
    % disponíveis. O 2SLS produz elasticidades economicamente razoáveis,
    % gerando ξ̂ mais limpos e Ω̂ mais representativa.
    %
    % Fallback: se 2SLS não disponível, usa passo 1.
    % A teoria de GMM (Hansen, 1982) permite qualquer estimador consistente
    % no primeiro estágio para construção de Ŵ.
    
    if ~isempty(config.beta_2sls) && numel(config.beta_2sls) == 5
        beta_for_W = config.beta_2sls;
        W_source = '2SLS';
    else
        beta_for_W = beta_s1;
        W_source = 'Passo 1 (W=I)';
    end
    
    if config.verbose
        fprintf('   Fonte de ξ̂ para Ω̂: %s\n', W_source);
        fprintf('   β_W = [%.4f, %.4f, %.4f, %.4f, %.4f]\n', ...
            beta_for_W(1), beta_for_W(2), beta_for_W(3), beta_for_W(4), beta_for_W(5));
    end
    
    % Computar ξ̂ no β escolhido (via caminho rápido)
    xi_for_W = compute_xi_fast(beta_for_W, precomp, p_markov);
    
    % Selecionar ξ̂ nas obs válidas para momentos
    xi_mom = xi_for_W(precomp.valid_moments);
    Z      = precomp.Z;
    N_mom  = precomp.n_valid_moments;
    M      = precomp.n_moments;
    
    % Ω̂ = (1/N) Σ (Zᵢ·ξ̂ᵢ)(Zᵢ·ξ̂ᵢ)'   →   (M × M)
    % Eficiente: G = Z .* ξ̂,  Ω̂ = G'G / N
    G = Z .* xi_mom;       % (N_mom × M)
    Omega_hat = (G' * G) / N_mom;  % (M × M)
    
    % Regularização se mal-condicionada
    cond_Omega = cond(Omega_hat);
    if cond_Omega > 1e10
        ridge = 1e-6 * trace(Omega_hat) / M;
        Omega_hat = Omega_hat + ridge * eye(M);
        if config.verbose
            fprintf('   ⚠ Ω̂ mal-condicionada (cond=%.1e) — ridge=%.1e\n', ...
                cond_Omega, ridge);
        end
    end
    
    % Ŵ = Ω̂⁻¹
    W_opt = inv(Omega_hat);  %#ok<MINV>
    
    % Simetrizar (robustez numérica)
    W_opt = (W_opt + W_opt') / 2;
    
    if config.verbose
        fprintf('   Ω̂: %d×%d | cond(Ω̂) = %.2e | cond(Ŵ) = %.2e\n', ...
            M, M, cond(Omega_hat), cond(W_opt));
    end
    
    % =====================================================================
    % 8. PASSO 2: W = Ŵ (eficiente)
    % =====================================================================
    
    if config.verbose
        fprintf('\n── PASSO 2: W = Ŵ (eficiente) ─────────\n');
    end
    
    % Starts para o passo 2:
    %   #1: ótimo do passo 1 (melhor palpite)
    %   #2: seed 2SLS (se disponível)
    %   #3-N: perturbações em torno do ótimo do passo 1
    n_starts_s2 = config.n_starts_step2;
    starts_theta_s2 = zeros(n_starts_s2, 5);
    
    % Start 1: ótimo do passo 1
    starts_theta_s2(1, :) = beta_step1;
    
    % Start 2: seed 2SLS
    s2_next = 2;
    if ~isempty(config.beta_2sls) && numel(config.beta_2sls) == 5
        starts_theta_s2(2, :) = beta2theta(clip_beta(config.beta_2sls));
        s2_next = 3;
    end
    
    % Starts restantes: perturbações em torno do ótimo do passo 1
    beta_s1_clipped = clip_beta(beta_s1);
    for s = s2_next:n_starts_s2
        perturb = beta_s1_clipped + 0.05 * randn(1,5) .* (bounds.ub - bounds.lb);
        starts_theta_s2(s, :) = beta2theta(clip_beta(perturb));
    end
    
    [beta_step2, fval_step2, all_results_s2, elapsed_s2] = ...
        run_multistart(obj_fun_factory(precomp, p_markov, bounds, W_opt), ...
                       starts_theta_s2, config, theta2beta);
    
    beta_opt = theta2beta(beta_step2);
    theta_opt = beta_step2;
    best_fval = fval_step2;
    
    if config.verbose
        fprintf('   Passo 2 concluído em %.1f s\n', elapsed_s2);
        fprintf('   β₂ = [%.4f, %.4f, %.4f, %.4f, %.4f] | Q₂ = %.6e\n', ...
            beta_opt(1), beta_opt(2), beta_opt(3), beta_opt(4), beta_opt(5), fval_step2);
        
        % Comparação passo 1 vs 2
        delta = beta_opt - beta_s1;
        fprintf('   Δβ (passo2 − passo1) = [%+.4f, %+.4f, %+.4f, %+.4f, %+.4f]\n', ...
            delta(1), delta(2), delta(3), delta(4), delta(5));
    end
    
else
    % Modo single-step: resultado do passo 1 é final
    beta_opt  = beta_s1;
    theta_opt = beta_step1;
    best_fval = fval_step1;
    W_opt     = [];
    all_results_s2 = {};
    elapsed_s2     = 0;
    fval_step2     = NaN;
end

% =========================================================================
% 9. RECUPERAR GRANDEZAS NO ÓTIMO
% =========================================================================

if config.verbose
    fprintf('\n── DIAGNÓSTICOS FINAIS ─────────────────\n');
end

config_final         = config;
config_final.lag_map = build_lag_map(data);
config_final.verbose = false;

phi_opt  = compute_phi(data, beta_opt);
[xi_opt, omega_opt, ~] = compute_innovation(data, phi_opt, config_final);
[g_opt, ~, ~]          = compute_moments(data, xi_opt, config_final);

valid   = ~isnan(xi_opt);
n_valid = sum(valid);

xi_valid = xi_opt(valid);
omega_v  = omega_opt(valid);
SS_res   = sum(xi_valid.^2);
SS_tot   = sum((omega_v - mean(omega_v)).^2);
rsquared = 1 - SS_res / SS_tot;
rmse     = sqrt(mean(xi_valid.^2));

% ── Teste J de Hansen (sobre-identificação) ──
n_params  = 5;
n_moments = numel(g_opt);
df_J      = n_moments - n_params;

if config.two_step && ~isempty(W_opt)
    J_stat = precomp.n_valid_moments * (g_opt' * W_opt * g_opt);
    J_pval = 1 - chi2cdf(J_stat, df_J);
else
    J_stat = NaN;
    J_pval = NaN;
end

if config.verbose
    fprintf('   β_v  = %.6f\n', beta_opt(1));
    fprintf('   β_k  = %.6f\n', beta_opt(2));
    fprintf('   β_vv = %.6f\n', beta_opt(3));
    fprintf('   β_kk = %.6f\n', beta_opt(4));
    fprintf('   β_vk = %.6f\n', beta_opt(5));
    fprintf('   β_v + β_k = %.4f (retornos de escala lineares)\n', beta_opt(1) + beta_opt(2));
    fprintf('   ||g(β̂)|| = %.6e\n', norm(g_opt));
    fprintf('   R² Markov = %.4f | RMSE(ξ) = %.4f\n', rsquared, rmse);
    fprintf('   n_obs=%d | n_valid=%d | M=%d momentos\n', n_obs, n_valid, n_moments);
    fprintf('   Sobre-identificação: %d - %d = %d g.l.\n', n_moments, n_params, df_J);
    
    if config.two_step
        fprintf('   Teste J de Hansen: J=%.3f | p-valor=%.4f', J_stat, J_pval);
        if J_pval < 0.05
            fprintf(' ⚠ rejeita H₀ a 5%%');
        else
            fprintf(' ✓ não rejeita H₀');
        end
        fprintf('\n');
    end
    
    % Verificar bounds (usar tolerância relativa à amplitude)
    bound_range = bounds.ub - bounds.lb;
    at_lb = beta_opt <= bounds.lb + 0.01 * bound_range;
    at_ub = beta_opt >= bounds.ub - 0.01 * bound_range;
    if any(at_lb) || any(at_ub)
        labels = {'β_v','β_k','β_vv','β_kk','β_vk'};
        for j = 1:5
            if at_lb(j)
                fprintf('   ⚠ %s = %.4f no lower bound (%.2f)\n', labels{j}, beta_opt(j), bounds.lb(j));
            end
            if at_ub(j)
                fprintf('   ⚠ %s = %.4f no upper bound (%.2f)\n', labels{j}, beta_opt(j), bounds.ub(j));
            end
        end
    end
    
    % Sumário multi-start passo final
    final_results = all_results_s2;
    if isempty(final_results), final_results = all_results_s1; end
    n_st = length(final_results);
    fvals = NaN(n_st, 1);
    n_converged = 0;
    for s = 1:n_st
        if ~isempty(final_results{s})
            fvals(s) = final_results{s}.fval;
            n_converged = n_converged + 1;
        end
    end
    fvals_valid = fvals(~isnan(fvals));
    if numel(fvals_valid) > 1
        fprintf('   Multi-start: %d/%d convergiram | Q range [%.2e, %.2e]\n', ...
            n_converged, n_st, min(fvals_valid), max(fvals_valid));
        near_best = sum(fvals_valid < min(fvals_valid) * 1.05);
        fprintf('   Starts dentro de 5%% do ótimo: %d/%d\n', near_best, n_converged);
    end
    
    fprintf('\n========================================\n');
    fprintf('GMM-ACF %s CONCLUÍDO\n', ...
        ternary(config.two_step, 'TWO-STEP', 'W=I'));
    fprintf('========================================\n\n');
end

% =========================================================================
% 10. EMPACOTAR OUTPUTS
% =========================================================================

params = struct();
params.beta0      = NaN;
params.beta_v     = beta_opt(1);
params.beta_k     = beta_opt(2);
params.beta_vv    = beta_opt(3);
params.beta_kk    = beta_opt(4);
params.beta_vk    = beta_opt(5);
params.beta_omega = 1.0;

diagnostics = struct();
diagnostics.method           = ternary(config.two_step, 'GMM_ACF_TwoStep', 'GMM_ACF_W_identity');
diagnostics.fval             = best_fval;
diagnostics.exitflag         = 1;
diagnostics.iterations       = 0;
diagnostics.funcCount        = 0;
diagnostics.elapsed_sec      = elapsed_s1 + elapsed_s2;
diagnostics.n_obs            = n_obs;
diagnostics.n_valid          = n_valid;
diagnostics.n_moments        = n_moments;
diagnostics.n_lags           = config.n_lags;
diagnostics.g_at_optimum     = g_opt;
diagnostics.norm_g           = norm(g_opt);
diagnostics.omega_hat        = omega_opt;
diagnostics.omega_mean       = mean(omega_opt(valid));
diagnostics.omega_std        = std(omega_opt(valid));
diagnostics.xi_hat           = xi_opt;
diagnostics.rsquared         = rsquared;
diagnostics.rmse             = rmse;
diagnostics.residuals        = xi_opt;
diagnostics.n_vars           = 5;
diagnostics.n_instruments    = n_moments;
diagnostics.n_starts         = config.n_starts;
diagnostics.all_results      = all_results_s1;
diagnostics.bounds           = bounds;
diagnostics.beta_opt_bounded = beta_opt;
diagnostics.theta_opt        = theta_opt;
diagnostics.f_stats_first_stage = [];
diagnostics.f_stat_mean      = NaN;
diagnostics.weak_instruments = false;

% Two-step específicos
diagnostics.two_step         = config.two_step;
diagnostics.beta_step1       = beta_s1;
diagnostics.fval_step1       = fval_step1;
diagnostics.fval_step2       = fval_step2;
diagnostics.all_results_s2   = all_results_s2;
diagnostics.J_stat           = J_stat;
diagnostics.J_pval           = J_pval;
diagnostics.J_df             = df_J;
if config.two_step
    diagnostics.W_optimal    = W_opt;
    diagnostics.Omega_hat    = Omega_hat;
    diagnostics.W_source     = W_source;
    diagnostics.beta_for_W   = beta_for_W;
end

end


% =========================================================================
% FUNÇÕES AUXILIARES INTERNAS
% =========================================================================

function f = obj_fun_factory(precomp, p_markov, bounds, W)
    %OBJ_FUN_FACTORY Cria handle de função objetivo para fminsearch
    if isempty(W)
        f = @(th) objective_gmm_fast(th, precomp, p_markov, bounds);
    else
        f = @(th) objective_gmm_fast(th, precomp, p_markov, bounds, W);
    end
end


function [best_theta, best_fval, all_results, elapsed] = ...
    run_multistart(obj_fun, starts_theta, config, theta2beta)
    %RUN_MULTISTART Executa multi-start Nelder-Mead + refinamento
    
    n_starts = size(starts_theta, 1);
    bounds   = config.bounds;
    
    options = optimset('fminsearch');
    options.MaxIter     = config.max_iter;
    options.MaxFunEvals = config.max_iter * 10;
    options.TolFun      = config.tol_fun;
    options.TolX        = config.tol_x;
    options.Display     = 'off';
    
    if config.verbose
        fprintf('   Multi-start (%d starts | max_iter=%d)\n', n_starts, config.max_iter);
        fprintf('   %-6s  %-12s  %-8s  %-44s\n', ...
            'Start', 'Q(β)', 'Flag', 'β = [β_v, β_k, β_vv, β_kk, β_vk]');
        fprintf('   %s\n', repmat('-', 1, 76));
    end
    
    best_fval   = Inf;
    best_theta  = starts_theta(1, :);
    all_results = cell(n_starts, 1);
    
    tic;
    for s = 1:n_starts
        try
            [theta_s, fval_s, exit_s, output_s] = fminsearch(obj_fun, starts_theta(s,:), options);
        catch ME
            if config.verbose
                fprintf('   %-6d  ERRO: %s\n', s, ME.message);
            end
            continue
        end
        
        beta_s = theta2beta(theta_s);
        all_results{s} = struct('beta', beta_s, 'theta', theta_s, ...
                                'fval', fval_s, 'exitflag', exit_s, 'output', output_s);
        
        if config.verbose
            fprintf('   %-6d  %-12.6e  %-8d  [%.4f, %.4f, %.4f, %.4f, %.4f]', ...
                s, fval_s, exit_s, beta_s(1), beta_s(2), beta_s(3), beta_s(4), beta_s(5));
            if fval_s < best_fval
                fprintf('  *');
            end
            fprintf('\n');
        end
        
        if fval_s < best_fval
            best_fval  = fval_s;
            best_theta = theta_s;
        end
    end
    
    % Refinamento
    if config.verbose
        fprintf('   %s\n', repmat('-', 1, 76));
        fprintf('   Melhor Q = %.6e | Refinando...\n', best_fval);
    end
    
    options_ref = options;
    options_ref.MaxIter     = config.max_iter * 2;
    options_ref.MaxFunEvals = config.max_iter * 20;
    options_ref.TolFun      = config.tol_fun / 10;
    options_ref.TolX        = config.tol_x / 10;
    
    [theta_ref, fval_ref] = fminsearch(obj_fun, best_theta, options_ref);
    
    if fval_ref < best_fval
        best_fval  = fval_ref;
        best_theta = theta_ref;
        if config.verbose
            fprintf('   Refinamento melhorou: Q = %.6e\n', best_fval);
        end
    else
        if config.verbose
            fprintf('   Refinamento sem melhoria (Q = %.6e)\n', best_fval);
        end
    end
    
    elapsed = toc;
end


function xi_full = compute_xi_fast(beta, precomp, p_markov)
    %COMPUTE_XI_FAST Computa ξ(β) usando caminho rápido (vetorial)
    %  Retorna vetor N×1 com NaN onde lag não existe.
    
    phi = precomp.log_q - (beta(1) .* precomp.log_v       + ...
                           beta(2) .* precomp.log_k       + ...
                           beta(3) .* precomp.log_v.^2    + ...
                           beta(4) .* precomp.log_k.^2    + ...
                           beta(5) .* precomp.log_v .* precomp.log_k);
    
    omega = phi;
    valid_mk   = precomp.valid_markov;
    omega_curr = omega(valid_mk);
    omega_prev = omega(precomp.omega_lag_idx(valid_mk));
    
    n_valid = precomp.n_valid_markov;
    X_mk = ones(n_valid, p_markov + 1);
    for j = 1:p_markov
        X_mk(:, j+1) = omega_prev .^ j;
    end
    
    xi_mk = omega_curr - X_mk * (X_mk \ omega_curr);
    
    xi_full = NaN(precomp.n_obs, 1);
    xi_full(valid_mk) = xi_mk;
end


function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
