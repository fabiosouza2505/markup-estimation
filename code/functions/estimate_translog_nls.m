function [params, diagnostics] = estimate_translog_nls(data, config)
    %ESTIMATE_TRANSLOG_NLS Estima função translog via NLS (fminsearch)
    %
    % Função de produção Translog:
    % log(Q) = β₀ + β_v·log(V) + β_k·log(K) + 
    %          ½·β_vv·log(V)² + ½·β_kk·log(K)² + β_vk·log(V)·log(K) + ε
    %
    % Inputs:
    %   data - Tabela com variáveis já transformadas (log_receita, etc)
    %   config - Configurações da estimação
    %
    % Outputs:
    %   params - Parâmetros estimados
    %   diagnostics - Diagnósticos da estimação
    
    % Extrair variáveis
    y = data.log_receita;
    log_v = data.log_variable_input;
    log_k = data.log_capital;
    n = length(y);
    
    % =====================================================================
    % VALORES INICIAIS (Cobb-Douglas como chute)
    % =====================================================================
    
    % Regressão OLS simples para inicialização
    X_cd = [ones(n, 1), log_v, log_k];
    beta_init_cd = X_cd \ y;  % Solução OLS
    
    % Chute inicial para parâmetros translog
    theta0 = [
        beta_init_cd(1);    % beta0 (constante)
        beta_init_cd(2);    % beta_v (coef linear V)
        beta_init_cd(3);    % beta_k (coef linear K)
        0.01;               % beta_vv (termo quadrático V)
        0.01;               % beta_kk (termo quadrático K)
        0.01                % beta_vk (interação V-K)
    ];
    
    % =====================================================================
    % FUNÇÃO OBJETIVO
    % =====================================================================
    
    % Função que calcula SSR (soma dos quadrados dos resíduos)
    objective = @(theta) sum_squared_residuals(theta, y, log_v, log_k);
    
    % =====================================================================
    % OTIMIZAÇÃO
    % =====================================================================
    
    % Opções do fminsearch
    options = optimset(...
        'Display', config.optim_display, ...
        'MaxIter', config.max_iter, ...
        'MaxFunEvals', config.max_iter * 10, ...
        'TolFun', 1e-8, ...
        'TolX', 1e-8);
    
    % Executar otimização
    try
        [theta_opt, fval, exitflag, output] = fminsearch(objective, theta0, options);
        
        if exitflag ~= 1 && config.verbose
            warning('fminsearch não convergiu adequadamente (exitflag = %d)', exitflag);
        end
        
        % =====================================================================
        % ARMAZENAR PARÂMETROS
        % =====================================================================
        
        params = struct();
        params.beta0 = theta_opt(1);
        params.beta_v = theta_opt(2);
        params.beta_k = theta_opt(3);
        params.beta_vv = theta_opt(4);
        params.beta_kk = theta_opt(5);
        params.beta_vk = theta_opt(6);
        
        % =====================================================================
        % DIAGNÓSTICOS
        % =====================================================================
        
        % Predições
        y_pred = predict_translog(theta_opt, log_v, log_k);
        resid = y - y_pred;
        
        % R²
        SS_res = sum(resid.^2);
        SS_tot = sum((y - mean(y)).^2);
        rsquared = 1 - SS_res / SS_tot;
        
        % Armazenar diagnósticos
        diagnostics = struct();
        diagnostics.fval = fval;
        diagnostics.exitflag = exitflag;
        diagnostics.iterations = output.iterations;
        diagnostics.funcCount = output.funcCount;
        diagnostics.rsquared = rsquared;
        diagnostics.rmse = sqrt(mean(resid.^2));
        diagnostics.resid = resid;
        diagnostics.n_obs = n;
        
    catch ME
        warning('Erro na estimação: %s', ME.message);
        params = [];
        diagnostics = [];
    end
end

%% FUNÇÕES AUXILIARES

function ssr = sum_squared_residuals(theta, y, log_v, log_k)
    %SUM_SQUARED_RESIDUALS Calcula SSR para minimização
    y_pred = predict_translog(theta, log_v, log_k);
    resid = y - y_pred;
    ssr = sum(resid.^2);
end

function y_pred = predict_translog(theta, log_v, log_k)
    %PREDICT_TRANSLOG Prediz log(receita) usando função translog
    %
    % log(Q) = β₀ + β_v·V + β_k·K + ½·β_vv·V² + ½·β_kk·K² + β_vk·V·K
    % onde V = log(variable_input) e K = log(capital)
    
    beta0 = theta(1);
    beta_v = theta(2);
    beta_k = theta(3);
    beta_vv = theta(4);
    beta_kk = theta(5);
    beta_vk = theta(6);
    
    y_pred = beta0 + ...
             beta_v .* log_v + ...
             beta_k .* log_k + ...
             0.5 * beta_vv .* (log_v.^2) + ...
             0.5 * beta_kk .* (log_k.^2) + ...
             beta_vk .* log_v .* log_k;
end