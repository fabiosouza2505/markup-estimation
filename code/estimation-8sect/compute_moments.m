function [g_mean, g_matrix, Z] = compute_moments(data, xi, config)
%COMPUTE_MOMENTS Condições de momento do GMM-ACF — 6 instrumentos parcimoniosos
%
% Calcula o vetor de momentos:
%   g(β) = (1/N) Σᵢₜ Zᵢₜ · ξᵢₜ(β)
%
% INSTRUMENTOS (6 condições de momento — conjunto parcimonioso):
%
%     1. k_it              capital contemporâneo (predeterminado)
%     2. k_{it-1}          capital defasado
%     3. v_{it-1}          insumo variável defasado (1 período)
%     4. v_{it-2}          insumo variável defasado (2 períodos)
%     5. v_{it-1}²         quadrático do lag 1
%     6. v_{it-1}·k_it     interação lag 1 × capital
%
% Com 5 parâmetros (Translog), temos 1 grau de liberdade para o teste J.
%
% Validade:
%   k_it é predeterminado (decisão em t-1) → ortogonal a ξᵢₜ
%   V_{it-j} para j≥1 foi escolhido antes de ξᵢₜ → ortogonal a ξᵢₜ
%
% PERFORMANCE: Usa containers.Map (via build_lag_map) para lookup O(1).
%
% INPUTS:
%   data    - Tabela com: log_v, log_k, empresa, ano, (trimestre)
%   xi      - Vetor (N × 1) com inovação ξᵢₜ(β) de compute_innovation
%   config  - Struct com campos opcionais:
%               n_lags  : número de lags temporais a construir (default: 5)
%               verbose : exibir diagnósticos (default: false)
%               lag_map : containers.Map pré-construído (opcional)
%
% OUTPUTS:
%   g_mean   - Vetor (6 × 1) com condições de momento médias g(β)
%   g_matrix - Matriz (N_valid × 6) com Zᵢₜ · ξᵢₜ por observação
%   Z        - Matriz (N_valid × 6) de instrumentos nas obs válidas
%
% REFERÊNCIA:
%   Ackerberg, Caves & Frazer (2015), Econometrica, Eq. (14)
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

% =========================================================================
% CONFIGURAÇÃO
% =========================================================================

if nargin < 3 || isempty(config)
    config = struct();
end
if ~isfield(config, 'verbose'), config.verbose = false; end
if ~isfield(config, 'n_lags'),  config.n_lags  = 5;     end

n_lags = config.n_lags;

% =========================================================================
% VALIDAÇÃO
% =========================================================================

required_vars = {'log_v', 'log_k', 'empresa', 'ano'};
for i = 1:length(required_vars)
    if ~ismember(required_vars{i}, data.Properties.VariableNames)
        error('compute_moments: variável ''%s'' não encontrada.', required_vars{i});
    end
end

n_obs = height(data);
if numel(xi) ~= n_obs
    error('compute_moments: xi deve ter o mesmo número de linhas que data.');
end

% =========================================================================
% CONSTRUIR MAPA DE LOOKUP (ou reutilizar)
% =========================================================================

if isfield(config, 'lag_map') && ~isempty(config.lag_map)
    lag_map = config.lag_map;
else
    lag_map = build_lag_map(data);
end

% =========================================================================
% LAGS MÚLTIPLOS DO INSUMO VARIÁVEL E CAPITAL (via containers.Map)
%
% Constrói 5 lags temporais (t-1 a t-5) respeitando fronteiras de firma.
% Para cada observação, retrocede j trimestres usando prev_quarter_j.
% =========================================================================

log_v = data.log_v;
log_k = data.log_k;
anos  = data.ano;
trimestres = get_trimestre(data);
empresa_ids = normalize_empresa_ids(data.empresa);

% Matrizes de lags: cada coluna j contém o lag de j períodos
log_v_lags = NaN(n_obs, n_lags);   % V_{t-1} ... V_{t-5}
log_k_lag1 = NaN(n_obs, 1);        % K_{t-1} (apenas 1 lag de capital)

for idx = 1:n_obs
    emp_id = empresa_ids(idx);
    ano_j  = anos(idx);
    tri_j  = trimestres(idx);
    
    for j = 1:n_lags
        [ano_j_prev, tri_j_prev] = prev_quarter(ano_j, tri_j);
        key = sprintf('%d_%d_%d', emp_id, ano_j_prev, tri_j_prev);
        
        if lag_map.isKey(key)
            lag_idx = double(lag_map(key));
            log_v_lags(idx, j) = log_v(lag_idx);
            if j == 1
                log_k_lag1(idx) = log_k(lag_idx);
            end
        else
            % Gap no painel — lags de ordem > j também serão NaN
            break
        end
        
        % Avançar para o próximo período anterior
        ano_j = ano_j_prev;
        tri_j = tri_j_prev;
    end
end

% =========================================================================
% SELECIONAR OBSERVAÇÕES VÁLIDAS
%
% Obs válida: ξᵢₜ não é NaN E os 2 primeiros lags de V existem E K_{t-1} existe
% =========================================================================

valid = ~isnan(xi) & ~isnan(log_k_lag1) & all(~isnan(log_v_lags(:, 1:min(2,n_lags))), 2);
n_valid = sum(valid);

if n_valid < 20
    error('compute_moments: observações válidas insuficientes (%d). Mínimo: 20.', n_valid);
end

xi_v     = xi(valid);
log_k_v  = log_k(valid);
log_kl_v = log_k_lag1(valid);

% Extrair lags válidos
log_v_lags_v = log_v_lags(valid, :);   % (n_valid × n_lags)

% =========================================================================
% CONSTRUÇÃO DA MATRIZ DE INSTRUMENTOS Z (N_valid × 6)
%
% Z = [k_it, k_{it-1}, v_{it-1}, v_{it-2}, v_{it-1}², v_{it-1}·k_it]
%
% Total: 6 instrumentos (parcimonioso)
% =========================================================================

log_v_lag1 = log_v_lags_v(:, 1);
log_v_lag2 = log_v_lags_v(:, 2);

Z = [log_k_v, ...               % k_it
     log_kl_v, ...              % k_{it-1}
     log_v_lag1, ...            % v_{it-1}
     log_v_lag2, ...            % v_{it-2}
     log_v_lag1.^2, ...         % v_{it-1}²
     log_v_lag1 .* log_k_v];    % v_{it-1} · k_it

% =========================================================================
% CONDIÇÕES DE MOMENTO
%
% g_matrix (N × M): cada linha é Zᵢₜ · ξᵢₜ
% g_mean   (M × 1): média das condições de momento
% =========================================================================

g_matrix = Z .* xi_v;          % broadcasting: cada coluna de Z × ξ
g_mean   = mean(g_matrix, 1)'; % vetor coluna (M × 1)

% =========================================================================
% DIAGNÓSTICOS
% =========================================================================

if config.verbose
    n_moments = size(Z, 2);
    fprintf('   [Momentos] n_válido=%d | M=%d instrumentos (parcimonioso)\n', ...
        n_valid, n_moments);
    fprintf('   ||g(β)||  = %.6f\n', norm(g_mean));
    fprintf('   Z = [k_it, k_{t-1}, v_{t-1}, v_{t-2}, v_{t-1}², v_{t-1}·k_it]\n');
end

end


% =========================================================================
% FUNÇÃO AUXILIAR: Normaliza identificador de firma para vetor numérico
% =========================================================================
function ids_num = normalize_empresa_ids(empresa)

    if isnumeric(empresa)
        ids_num = double(empresa);
    elseif iscell(empresa)
        [~, ~, ids_num] = unique(empresa);
        ids_num = double(ids_num);
    elseif isstring(empresa) || ischar(empresa)
        [~, ~, ids_num] = unique(empresa);
        ids_num = double(ids_num);
    elseif iscategorical(empresa)
        ids_num = double(empresa);
    else
        try
            ids_num = double(empresa);
        catch
            error('normalize_empresa_ids: tipo não suportado: %s', class(empresa));
        end
    end
end


% =========================================================================
% FUNÇÃO AUXILIAR: Retorna (ano, trimestre) do período imediatamente anterior
% =========================================================================
function [ano_ant, tri_ant] = prev_quarter(ano, tri)
    if tri > 1
        ano_ant = ano;
        tri_ant = tri - 1;
    else
        ano_ant = ano - 1;
        tri_ant = 4;
    end
end


% =========================================================================
% FUNÇÃO AUXILIAR: Extrai vetor de trimestres da tabela (com fallback)
% =========================================================================
function trimestres = get_trimestre(data)
    if ismember('trimestre', data.Properties.VariableNames)
        trimestres = data.trimestre;
    else
        trimestres = zeros(height(data), 1);
        warning('compute_moments: coluna ''trimestre'' não encontrada. Usando lag anual.');
    end
end
