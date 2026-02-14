function [params, diagnostics] = estimate_translog_nls(data, config)
    %ESTIMATE_TRANSLOG_NLS Estima função Translog via NLS (fminsearch)
    %
    % Função de produção Translog (parametrização consistente com 2SLS):
    %   log(Q) = b0 + bv*log(V) + bk*log(K) +
    %            bvv*log(V)^2 + bkk*log(K)^2 + bvk*log(V)*log(K) + e

    %
    % INPUTS:
    %   data   - Tabela com: log_receita, log_variable_input, log_capital
    %   config - Struct com configuracoes (opcional):
    %            - verbose (bool)
    %            - max_iter (int, default: 10000)
    %            - optim_display (char, default: 'off')
    %
    % OUTPUTS:
    %   params      - Struct com coeficientes (mesma estrutura do 2SLS):
    %                 beta0, beta_k, beta_kk, beta_omega, beta_v, beta_vv, beta_vk
    %   diagnostics - Struct com diagnosticos:
    %                 rsquared, rmse, residuals, n_obs, omega_hat, etc.
    %
    % REFERENCIA:
    %   De Loecker, J., & Warzynski, F. (2012). Markups and firm-level
    %   export status. American Economic Review, 102(6), 2437-2471.
    %
    % Autor: Fabio de Medeiros Souza
    % Data: Fevereiro 2025

    % =====================================================================
    % CONFIGURACOES
    % =====================================================================
    
    if nargin < 2, config = struct(); end
    if ~isfield(config, 'verbose'),        config.verbose = true;          end
    if ~isfield(config, 'max_iter'),       config.max_iter = 10000;        end
    if ~isfield(config, 'optim_display'),  config.optim_display = 'off';   end
    
    % =====================================================================
    % 1. EXTRAIR DADOS
    % =====================================================================
    
    if config.verbose
        fprintf('1. Extraindo dados...\n');
    end
    
    y     = data.log_receita;
    log_v = data.log_variable_input;
    log_k = data.log_capital;
    n     = length(y);
    
    if config.verbose
        fprintf('   N = %d observacoes\n', n);
        fprintf('   Validacao concluida\n\n');
    end
    
    % =====================================================================
    % 2. VALORES INICIAIS (Cobb-Douglas como chute)
    % =====================================================================
    
    if config.verbose
        fprintf('2. Calculando valores iniciais (OLS Cobb-Douglas)...\n');
    end
    
    X_cd = [ones(n, 1), log_v, log_k];
    beta_init_cd = X_cd \ y;
    
    % Vetor de parametros: [b0, bv, bk, bvv, bkk, bvk]
    theta0 = [
        beta_init_cd(1);    % beta0
        beta_init_cd(2);    % beta_v
        beta_init_cd(3);    % beta_k
        0.01;               % beta_vv (sem 1/2)
        0.01;               % beta_kk (sem 1/2)
        0.01                % beta_vk
    ];
    
    if config.verbose
        fprintf('   Chute inicial: bv=%.3f, bk=%.3f\n', theta0(2), theta0(3));
        fprintf('   Valores iniciais definidos\n\n');
    end
    
    % =====================================================================
    % 3. OTIMIZACAO VIA FMINSEARCH
    % =====================================================================
    
    if config.verbose
        fprintf('3. Executando NLS (fminsearch)...\n');
    end
    
    % Funcao objetivo: soma de quadrados dos residuos
    objective = @(theta) sum((y - predict_translog(theta, log_v, log_k)).^2);
    
    % Opcoes
    options = optimset(...
        'Display', config.optim_display, ...
        'MaxIter', config.max_iter, ...
        'MaxFunEvals', config.max_iter * 10, ...
        'TolFun', 1e-8, ...
        'TolX', 1e-8);
    
    try
        [theta_opt, fval, exitflag, output] = fminsearch(objective, theta0, options);
    catch ME
        warning('Erro na otimizacao NLS: %s', ME.message);
        params = struct();
        diagnostics = struct();
        diagnostics.rsquared = NaN;
        diagnostics.rmse = NaN;
        return;
    end
    
    if exitflag ~= 1 && config.verbose
        fprintf('   fminsearch: exitflag = %d (convergencia parcial)\n', exitflag);
    end
    
    if config.verbose
        fprintf('   Iteracoes: %d | Avaliacoes: %d\n', ...
                output.iterations, output.funcCount);
        fprintf('   Otimizacao concluida\n\n');
    end
    
    % =====================================================================
    % 4. ESTIMAR PRODUTIVIDADE (RESIDUO)
    % =====================================================================
    
    if config.verbose
        fprintf('4. Estimando produtividade...\n');
    end
    
    y_pred = predict_translog(theta_opt, log_v, log_k);
    residuals = y - y_pred;
    
    % Produtividade = residuo da funcao de producao
    omega_hat = residuals;
    
    if config.verbose
        fprintf('   omega medio: %.4f (sigma = %.4f)\n', mean(omega_hat), std(omega_hat));
        fprintf('   Produtividade estimada\n\n');
    end
    
    % =====================================================================
    % 5. ARMAZENAR PARAMETROS (mesma estrutura do 2SLS)
    % =====================================================================
    
    if config.verbose
        fprintf('5. Calculando diagnosticos...\n');
    end
    
    SS_res = sum(residuals.^2);
    SS_tot = sum((y - mean(y)).^2);
    rsquared = 1 - SS_res / SS_tot;
    rmse = sqrt(mean(residuals.^2));
    
    % Parametros - mesma ordem e nomes do 2SLS para compatibilidade
    params = struct();
    params.beta0     = theta_opt(1);    % Constante
    params.beta_k    = theta_opt(3);    % Capital
    params.beta_kk   = theta_opt(5);    % Capital ao quadrado
    params.beta_omega = 1.0;            % NLS: omega entra como residuo, coef implicito = 1
    params.beta_v    = theta_opt(2);    % Insumo variavel
    params.beta_vv   = theta_opt(4);    % Insumo variavel ao quadrado
    params.beta_vk   = theta_opt(6);    % Interacao VxK
    
    % Diagnosticos - campos compativeis com save_multiple_sectors_results
    diagnostics = struct();
    diagnostics.method       = 'NLS';
    diagnostics.rsquared     = rsquared;
    diagnostics.rmse         = rmse;
    diagnostics.residuals    = residuals;
    diagnostics.predictions  = y_pred;
    diagnostics.omega_hat    = omega_hat;
    diagnostics.omega_mean   = mean(omega_hat);
    diagnostics.omega_std    = std(omega_hat);
    diagnostics.n_obs        = n;
    diagnostics.n_vars       = 6;
    diagnostics.n_instruments = 0;          % NLS nao usa instrumentos
    diagnostics.f_stats_first_stage = [];   % N/A
    diagnostics.f_stat_mean  = NaN;         % N/A
    diagnostics.weak_instruments = false;   % N/A
    diagnostics.fval         = fval;
    diagnostics.exitflag     = exitflag;
    diagnostics.iterations   = output.iterations;
    diagnostics.funcCount    = output.funcCount;
    
    if config.verbose
        fprintf('   R2 = %.4f\n', rsquared);
        fprintf('   RMSE = %.4f\n', rmse);
        fprintf('\n');
        fprintf('========================================\n');
        fprintf('ESTIMACAO NLS CONCLUIDA COM SUCESSO\n');
        fprintf('========================================\n\n');
    end
    
end


% =========================================================================
% FUNCAO AUXILIAR: Predicao Translog
% =========================================================================
function y_pred = predict_translog(theta, log_v, log_k)
    % Parametrizacao direta (consistente com 2SLS):
    %   log(Q) = b0 + bv*V + bk*K + bvv*V^2 + bkk*K^2 + bvk*V*K
    %
    % A elasticidade dlog(Q)/dlog(V) = bv + 2*bvv*V + bvk*K
    
    y_pred = theta(1) + ...               % b0
             theta(2) .* log_v + ...       % bv*V
             theta(3) .* log_k + ...       % bk*K
             theta(4) .* log_v.^2 + ...    % bvv*V^2  (SEM 1/2)
             theta(5) .* log_k.^2 + ...    % bkk*K^2  (SEM 1/2)
             theta(6) .* log_v .* log_k;   % bvk*V*K
end
