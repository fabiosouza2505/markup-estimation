function [params, diagnostics] = estimate_translog(data, config)
    %ESTIMATE_TRANSLOG Despacha estimação Translog para o método configurado
    %
    % SINTAXE:
    %   [params, diagnostics] = estimate_translog(data, config)
    %
    % O campo config.method determina qual estimador é chamado:
    %   '2sls'  → estimate_translog_2sls(data, config)
    %   'nls'   → estimate_translog_nls(data, config)
    %
    % INPUTS:
    %   data   - Tabela com dados preparados
    %   config - Struct com config.method ('2sls' ou 'nls') e demais opções
    %
    % OUTPUTS:
    %   params      - Struct com coeficientes estimados
    %   diagnostics - Struct com diagnósticos (R², RMSE, F-stats, etc.)
    %
    % Autor: Fabio de Medeiros Souza
    % Data: Fevereiro 2025
    
    if ~isfield(config, 'method')
        config.method = '2sls';
    end
    
    switch lower(config.method)
        case '2sls'
            [params, diagnostics] = estimate_translog_2sls(data, config);
            
        case 'nls'
            [params, diagnostics] = estimate_translog_nls(data, config);
            
        otherwise
            error('Método inválido: ''%s''. Use ''2sls'' ou ''nls''.', config.method);
    end
end
