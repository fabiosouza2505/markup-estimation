% =========================================================================
% PATCH: estimate_translog.m — adicionar 'gmm_acf' ao dispatcher
%
% Substitua o bloco switch/case do arquivo estimate_translog.m existente
% pelo bloco abaixo, que adiciona o método GMM-ACF sem alterar nada do
% comportamento atual de '2sls' e 'nls'.
% =========================================================================

switch lower(config.method)
    case '2sls'
        [params, diagnostics] = estimate_translog_2sls(data, config);
        
    case 'nls'
        [params, diagnostics] = estimate_translog_nls(data, config);
        
    case 'gmm_acf'
        [params, diagnostics] = estimate_translog_gmm_acf(data, config);
        
    otherwise
        error('estimate_translog: método inválido: ''%s''. Use ''2sls'', ''nls'' ou ''gmm_acf''.', ...
              config.method);
end

% =========================================================================
% COMO USAR NO main.m:
%
%   config.method = 'gmm_acf';
%
%   % Opções específicas do GMM-ACF (todas opcionais):
%   config.markov_degree = 3;     % grau do polinômio de Markov (default: 3)
%   config.n_lags        = 5;     % lags temporais nos instrumentos (default: 5)
%   config.n_starts      = 10;    % pontos iniciais multi-start (default: 10)
%   config.max_iter      = 5000;  % iterações por start (default: 5000)
%   config.tol_fun       = 1e-10; % tolerância função objetivo (default: 1e-10)
%   config.seed_from_ols = true;  % usar OLS como ponto inicial #1 (default: true)
%
%   % O restante do pipeline é idêntico — calculate_markups_from_params_weighted
%   % e save_multiple_sectors_results funcionam sem alteração.
% =========================================================================
