function [params, diagnostics] = estimate_translog_2sls(data, config)
    %ESTIMATE_TRANSLOG_2SLS Estima função Translog via 2SLS
    %
    % Implementa metodologia de De Loecker & Warzynski (2012) para estimação
    % de markups usando função de produção Translog e instrumentos (lags)
    % para controlar endogeneidade.
    %
    % SINTAXE:
    %   [params, diagnostics] = estimate_translog_2sls(data, config)
    %
    % INPUTS:
    %   data   - Tabela MATLAB com variáveis:
    %            • log_receita (variável dependente)
    %            • log_variable_input (insumo variável)
    %            • log_capital (capital)
    %
    %   config - Struct com configurações (opcional):
    %            • verbose (bool): Exibir mensagens (default: true)
    %
    % OUTPUTS:
    %   params      - Struct com parâmetros estimados:
    %                 • beta0, beta_v, beta_k (coefs lineares)
    %                 • beta_vv, beta_kk, beta_vk (coefs quadráticos)
    %                 • beta_all (vetor completo)
    %
    %   diagnostics - Struct com estatísticas:
    %                 • rsquared, rmse (qualidade do ajuste)
    %                 • f_stats_first_stage (força dos instrumentos)
    %                 • weak_instruments (flag: true se F < 10)
    %
    % MÉTODO:
    %   1. Cria instrumentos usando lags dos insumos
    %   2. Primeiro estágio: regride X em Z (instrumentos)
    %   3. Segundo estágio: regride y em X_hat (valores preditos)
    %   4. Calcula diagnósticos (R², F-stats, etc)
    %
    % REFERÊNCIA:
    %   De Loecker, J., & Warzynski, F. (2012). Markups and firm-level 
    %   export status. American Economic Review, 102(6), 2437-2471.
    %
    % Autor: Fabio de Medeiros Souza
    % Data: Dezembro 2024
    
    % =========================================================================
    % CONFIGURAÇÕES INICIAIS
    % =========================================================================
    
    % Parâmetros default
    if nargin < 2 || ~isfield(config, 'verbose')
        config.verbose = true;
    end
    
    % =========================================================================
    % PASSO 1: EXTRAIR E VALIDAR DADOS
    % =========================================================================
    
    if config.verbose
        fprintf('1. Extraindo dados...\n');
    end
    
    % Extrair variáveis da tabela
    log_receita = data.log_receita;           % Y (output)
    log_v = data.log_variable_input;          % V (variable input)
    log_k = data.log_capital;                 % K (capital)

    % Extrair e converter identificador de empresa para numérico
    empresa_raw = data.empresa;
    if iscell(empresa_raw) || isstring(empresa_raw) || iscategorical(empresa_raw)
        [~, ~, empresa_id] = unique(string(empresa_raw));
    else
        empresa_id = empresa_raw;
    end
    
    n_original = length(log_receita);
    
    if config.verbose
        fprintf('   N original = %d observações\n', n_original);
    end
    
    % Validar dados
    if any(isnan(log_receita)) || any(isnan(log_v)) || any(isnan(log_k))
        error('Dados contêm NaN! Execute prepare_data_nls primeiro.');
    end
    
    if std(log_receita) == 0 || std(log_v) == 0 || std(log_k) == 0
        error('Variáveis sem variação! Impossível estimar.');
    end
    
    if config.verbose
        fprintf('   ✓ Validação concluída\n\n');
    end
    
    % =========================================================================
    % PASSO 2: ESTIMAR PRODUTIVIDADE (FORMA REDUZIDA)
    % =========================================================================
    
    if config.verbose
        fprintf('2. Estimando produtividade via forma reduzida...\n');
    end
    
    % Variáveis base para o polinômio
    state_var_cols = [log_k, log_k .^ 2];
    control_var_cols = [log_v, log_v .^ 2, log_v .* log_k];
    input_base = [state_var_cols, control_var_cols];
    % → 5 colunas: [K, K², V, V², V×K]
    
    % Construir polinômio de grau 3 (análogo a PolynomialFeatures(degree=3))
    % Inclui todos os termos até grau 3 das 5 variáveis base
    X_poly = build_polynomial_features(input_base, 3);
    % (ver função auxiliar abaixo)
    
    % Forma reduzida: log(receita) ~ polinômio
    beta_reduced = X_poly \ log_receita;
    y_pred_reduced = X_poly * beta_reduced;
    
    % Produtividade estimada = resíduo
    omega_hat = log_receita - y_pred_reduced;
    
    % Diagnósticos da forma reduzida 
    r2_reduced = 1 - sum(omega_hat.^2) / sum((log_receita - mean(log_receita)).^2);
    omega_mean = mean(omega_hat);
    omega_std = std(omega_hat);
    if config.verbose
        fprintf('   R² da forma reduzida: %.4f\n', r2_reduced);
        fprintf('   Produtividade: média=%.4f, std=%.4f\n', omega_mean, omega_std);
        fprintf('   ✓ Produtividade estimada\n\n');
    end

    % =========================================================================
    % PASSO 3: CRIAR INSTRUMENTOS (LAGS)
    % =========================================================================
    
    if config.verbose
        fprintf('3. Criando instrumentos via lags (respeitando painel)...\n');
    end
    
    % 5 lags do insumo variável, respeitando fronteiras entre empresas
    log_v_lag1 = group_lag(log_v, empresa_id, 1);
    log_v_lag2 = group_lag(log_v, empresa_id, 2);
    log_v_lag3 = group_lag(log_v, empresa_id, 3);
    log_v_lag4 = group_lag(log_v, empresa_id, 4);
    log_v_lag5 = group_lag(log_v, empresa_id, 5);

    % Lags ao quadrado (cada um individualmente)
    log_v_lag1_sq = log_v_lag1 .^ 2;
    log_v_lag2_sq = log_v_lag2 .^ 2;
    log_v_lag3_sq = log_v_lag3 .^ 2;
    log_v_lag4_sq = log_v_lag4 .^ 2;
    log_v_lag5_sq = log_v_lag5 .^ 2;

    % Interações: cada lag × capital contemporâneo
    log_v_lag1_k = log_v_lag1 .* log_k;
    log_v_lag2_k = log_v_lag2 .* log_k;
    log_v_lag3_k = log_v_lag3 .* log_k;
    log_v_lag4_k = log_v_lag4 .* log_k;
    log_v_lag5_k = log_v_lag5 .* log_k;    
    
    % Remover NaN no lag (lag5 é o mais restritivo)
    valid_mask = ~isnan(log_v_lag5);   
    valid_idx = find(valid_mask);

    % Variáveis principais
    log_receita = log_receita(valid_idx);
    log_v = log_v(valid_idx);
    log_k = log_k(valid_idx);
    omega_hat = omega_hat(valid_idx);

    % 5 lags lineares
    log_v_lag1 = log_v_lag1(valid_idx);
    log_v_lag2 = log_v_lag2(valid_idx);
    log_v_lag3 = log_v_lag3(valid_idx);
    log_v_lag4 = log_v_lag4(valid_idx);
    log_v_lag5 = log_v_lag5(valid_idx);

    % 5 lags quadráticos
    log_v_lag1_sq = log_v_lag1_sq(valid_idx);
    log_v_lag2_sq = log_v_lag2_sq(valid_idx);
    log_v_lag3_sq = log_v_lag3_sq(valid_idx);
    log_v_lag4_sq = log_v_lag4_sq(valid_idx);
    log_v_lag5_sq = log_v_lag5_sq(valid_idx);

    % 5 interações lag × capital
    log_v_lag1_k = log_v_lag1_k(valid_idx);
    log_v_lag2_k = log_v_lag2_k(valid_idx);
    log_v_lag3_k = log_v_lag3_k(valid_idx);
    log_v_lag4_k = log_v_lag4_k(valid_idx);
    log_v_lag5_k = log_v_lag5_k(valid_idx);    
    
    n = length(log_receita);
    
    if config.verbose
        fprintf('   Instrumentos criados');
        fprintf('   N (após remoção de lags) = %d\n', n);
    end
    
    % =========================================================================
    % PASSO 4: MONTAR MATRIZES DE REGRESSÃO
    % =========================================================================
    
    if config.verbose
        fprintf('4. Construindo matrizes...\n');
    end
    
    % Variável dependente (vetor n×1)
    y = log_receita;
    
    % Variáveis endógenas X (matriz n×6)
    % Função Translog: log(Q) = β₀ + β_v·V + β_k·K + β_vv·V² + β_kk·K² + β_vk·V·K
    % Variáveis exógenas
    X_exog = [
        ones(n, 1),           ...  % 1. Constante
        log_k,                ...  % 2. log(K)
        log_k .^ 2,           ...  % 3. log(K)²
        omega_hat             ...  % 4. Produtividade estimada
    ];

    % Variáveis endógenas (serão instrumentalizadas)
    X_endog = [
        log_v,                ...  % 1. log(V)
        log_v .^ 2,           ...  % 2. log(V)²
        log_v .* log_k        ...  % 3. log(V)×log(K)
    ];

    % X completo (para referência e predição final)
    X = [X_exog, X_endog];    
    
    % Instrumentos Z : constante + 18 instrumentos
    Z = [
        ones(n, 1),          ...  % 1. Constante
        log_k,               ...  % 2. Capital contemporâneo
        log_k .^ 2,          ...  % 3. Capital² contemporâneo
        log_v_lag1,           ...  % 4-8. Lags lineares
        log_v_lag2,           ...
        log_v_lag3,           ...
        log_v_lag4,           ...
        log_v_lag5,           ...
        log_v_lag1_sq,        ...  % 9-13. Lags quadráticos
        log_v_lag2_sq,        ...
        log_v_lag3_sq,        ...
        log_v_lag4_sq,        ...
        log_v_lag5_sq,        ...
        log_v_lag1_k,         ...  % 14-18. Interações lag×K
        log_v_lag2_k,         ...
        log_v_lag3_k,         ...
        log_v_lag4_k,         ...
        log_v_lag5_k,         ...
        omega_hat             ... % 19. Produtividade
    ];

    [n_obs, n_vars] = size(X);
    [~, n_instruments] = size(Z);
    
    if config.verbose
        fprintf('   Matriz X (endógenas): %d × %d\n', n_obs, n_vars);
        fprintf('   Matriz Z (instrumentos): %d × %d\n', n_obs, n_instruments);
        fprintf('   ✓ Matrizes construídas\n\n');
    end
    
    % =========================================================================
    % PASSO 5: ESTIMAÇÃO 2SLS (DOIS ESTÁGIOS)
    % =========================================================================
    
    if config.verbose
        fprintf('5. Executando 2SLS...\n');
    end
    
    % ─────────────────────────────────────────────────────────────────────────
    % PRIMEIRO ESTÁGIO: X = Z·π + v
    % ─────────────────────────────────────────────────────────────────────────
    % Objetivo: Obter X_hat = valores de X explicados apenas por Z
    % Isso "purifica" X da correlação com termo de erro
    
    if config.verbose
        fprintf('   Primeiro estágio: X ~ Z\n');
    end
    
    % Resolver: Z'Z·π = Z'X  →  π = (Z'Z)⁻¹·Z'X
    beta_first = Z \ X_endog;          % π = (Z'Z)⁻¹Z'X_endog
    X_endog_hat = Z * beta_first;      % valores preditos das endógenas
    
    % Valores preditos (fitted values)
    X_hat = [X_exog, X_endog_hat];
    
    % ─────────────────────────────────────────────────────────────────────────
    % SEGUNDO ESTÁGIO: y = X_hat·β + u
    % ─────────────────────────────────────────────────────────────────────────
    % Objetivo: Obter parâmetros finais usando X_hat ao invés de X
    
    if config.verbose
        fprintf('   Segundo estágio: y ~ X_hat\n');
    end
    
    % Resolver: X_hat'·X_hat·β = X_hat'·y  →  β = (X_hat'·X_hat)⁻¹·X_hat'·y
    beta_2sls = X_hat \ y;
    
    % Predições e resíduos
    y_pred = X * beta_2sls;        % Usar X original (não X_hat) para predição
    residuals = y - y_pred;
    
    if config.verbose
        fprintf('   ✓ 2SLS concluído\n\n');
    end
    
    % =========================================================================
    % PASSO 6: CALCULAR DIAGNÓSTICOS
    % =========================================================================
    
    if config.verbose
        fprintf('6. Calculando diagnósticos...\n');
    end
    
    % ─────────────────────────────────────────────────────────────────────────
    % R² (Coeficiente de Determinação)
    % ─────────────────────────────────────────────────────────────────────────
    SS_res = sum(residuals .^ 2);           % Soma dos quadrados dos resíduos
    SS_tot = sum((y - mean(y)) .^ 2);       % Soma total dos quadrados
    rsquared = 1 - SS_res / SS_tot;
    
    % ─────────────────────────────────────────────────────────────────────────
    % RMSE (Root Mean Square Error)
    % ─────────────────────────────────────────────────────────────────────────
    rmse = sqrt(mean(residuals .^ 2));
    
    % ─────────────────────────────────────────────────────────────────────────
    % F-statistics do Primeiro Estágio (Teste de instrumentos fracos)
    % ─────────────────────────────────────────────────────────────────────────
    % Regra: F > 10 indica instrumentos fortes
    
    n_endog = size(X_endog, 2);   % = 3
    f_stats = zeros(n_endog, 1);

    for j = 1:n_endog
        x_j = X_endog(:, j);
        beta_j = Z \ x_j;
        x_j_pred = Z * beta_j;
        resid_j = x_j - x_j_pred;

        ss_res_j = sum(resid_j .^ 2);
        ss_tot_j = sum((x_j - mean(x_j)) .^ 2);
        r2_j = 1 - ss_res_j / ss_tot_j;

        k = n_instruments - 1;
        f_stats(j) = (r2_j / k) / ((1 - r2_j) / (n - k - 1));
    end    
    
    f_stat_mean = mean(f_stats);
    weak_instruments = (f_stat_mean < 10);
    
    if config.verbose
        fprintf('   R² = %.4f\n', rsquared);
        fprintf('   RMSE = %.4f\n', rmse);
        fprintf('   F-stat (1º estágio) = %.2f\n', f_stat_mean);
        
        if weak_instruments
            fprintf('   ATENÇÃO: Instrumentos podem ser fracos (F < 10)\n');
        else
            fprintf('   ✓ Instrumentos são fortes (F > 10)\n');
        end
        
        fprintf('\n');
    end
    
    % =========================================================================
    % PASSO 6: ARMAZENAR RESULTADOS
    % =========================================================================
    
    % Parâmetros estimados
    params = struct();
    params.beta0  = beta_2sls(1);    % Constante       (exógena)
    params.beta_k  = beta_2sls(2);   % Coef linear K   (exógena)
    params.beta_kk = beta_2sls(3);   % Coef quadrático K² (exógena)
    params.beta_omega = beta_2sls(4);   % omega_hat
    params.beta_v  = beta_2sls(5);   % Coef linear V   (endógena)
    params.beta_vv = beta_2sls(6);   % Coef quadrático V² (endógena)
    params.beta_vk = beta_2sls(7);   % Coef interação V×K (endógena)    
    params.first_stage_coefs = beta_first;  % Coefs do 1º estágio
    params.beta_all = beta_2sls;  % Vetor completo [β0, βk, βkk, βω, βv, βvv, βvk]
    params.beta_names = {'beta0', 'beta_k', 'beta_kk', 'beta_omega', ...
                         'beta_v', 'beta_vv', 'beta_vk'};
    
    % Diagnósticos
    diagnostics = struct();
    diagnostics.method = '2SLS';
    diagnostics.rsquared = rsquared;
    diagnostics.rmse = rmse;
    diagnostics.residuals = residuals;
    diagnostics.omega_hat = omega_hat;       
    diagnostics.predictions = y_pred;
    diagnostics.f_stats_first_stage = f_stats;
    diagnostics.f_stat_mean = f_stat_mean;
    diagnostics.weak_instruments = weak_instruments;
    diagnostics.n_obs = n_obs;
    diagnostics.n_vars = n_vars;
    diagnostics.n_instruments = n_instruments;
    diagnostics.reduced_form_r2 = r2_reduced;
    diagnostics.omega_mean = omega_mean;
    diagnostics.omega_std = omega_std;
    
    if config.verbose
        fprintf('========================================\n');
        fprintf('✓ ESTIMAÇÃO 2SLS CONCLUÍDA COM SUCESSO\n');
        fprintf('========================================\n\n');
    end
    
end  % Fim da função estimate_translog_2sls
