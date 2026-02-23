function precomp = precompute_lags(data, n_lags)
%PRECOMPUTE_LAGS Pré-computa TODOS os índices e vetores de lag para o GMM-ACF
%
% Esta função é chamada UMA VEZ antes da otimização. Retorna uma struct
% com todos os vetores de lag pré-computados e máscara de validade,
% eliminando qualquer necessidade de containers.Map ou loops durante
% as iterações do fminsearch.
%
% PERFORMANCE:
%   Sem pré-computação: cada avaliação de Q(β) faz N×L lookups no Map
%   Com pré-computação: cada avaliação usa apenas indexação vetorial O(1)
%   Speedup estimado: 100-500× para painel de ~500 obs com 5 lags
%
% INPUTS:
%   data   - Tabela com: log_q, log_v, log_k, empresa, ano, (trimestre)
%   n_lags - Número de lags temporais (default: 5)
%
% OUTPUT:
%   precomp - Struct com campos:
%     .log_q         (N×1) log do produto
%     .log_v         (N×1) log do insumo variável
%     .log_k         (N×1) log do capital
%     .n_obs         escalar: total de observações
%
%     --- Lags para compute_innovation (Markov) ---
%     .omega_lag_idx (N×1) índice do lag de ω (NaN → sem lag)
%     .valid_markov  (N×1) logical: obs com lag de ω válido
%     .n_valid_markov escalar
%
%     --- Lags para compute_moments (instrumentos) ---
%     .log_v_lags    (N×n_lags) lags pré-computados de log_v
%     .log_k_lag1    (N×1) lag de 1 período de log_k
%     .valid_moments (N×1) logical: obs com TODOS os lags + lag de ω
%     .n_valid_moments escalar
%
%     --- Matriz Z pré-computada (parte que não depende de β) ---
%     .Z_capital     (N_valid × 3) [k_it, k_it², k_{it-1}]
%     .Z_v_lin       (N_valid × n_lags) lags lineares de V
%     .Z_v_sq        (N_valid × n_lags) lags quadráticos de V
%     .Z_v_k         (N_valid × n_lags) interações V_lag × k_it
%     .Z              (N_valid × M) matriz completa de instrumentos
%     .n_moments     escalar: número de condições de momento (18)
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

if nargin < 2, n_lags = 5; end

% =========================================================================
% 1. EXTRAIR VETORES
% =========================================================================

n_obs = height(data);
log_q = data.log_q;
log_v = data.log_v;
log_k = data.log_k;
anos  = data.ano;

if ismember('trimestre', data.Properties.VariableNames)
    trimestres = data.trimestre;
else
    trimestres = zeros(n_obs, 1);
    warning('precompute_lags: coluna ''trimestre'' ausente. Usando lag anual.');
end

% Normalizar empresa
empresa = data.empresa;
if isnumeric(empresa)
    emp_ids = double(empresa);
elseif iscell(empresa)
    [~, ~, emp_ids] = unique(empresa);
    emp_ids = double(emp_ids);
elseif isstring(empresa) || ischar(empresa)
    [~, ~, emp_ids] = unique(empresa);
    emp_ids = double(emp_ids);
elseif iscategorical(empresa)
    emp_ids = double(empresa);
else
    emp_ids = double(empresa);
end

% =========================================================================
% 2. CONSTRUIR MAPA DE LOOKUP (usado apenas aqui, uma vez)
% =========================================================================

lag_map = containers.Map('KeyType', 'char', 'ValueType', 'int32');
for idx = 1:n_obs
    key = sprintf('%d_%d_%d', emp_ids(idx), anos(idx), trimestres(idx));
    if ~lag_map.isKey(key)
        lag_map(key) = int32(idx);
    end
end

% =========================================================================
% 3. PRÉ-COMPUTAR ÍNDICES DE LAG (Markov: 1 lag de ω)
% =========================================================================

omega_lag_idx = NaN(n_obs, 1);

for idx = 1:n_obs
    [ano_ant, tri_ant] = prev_quarter(anos(idx), trimestres(idx));
    key = sprintf('%d_%d_%d', emp_ids(idx), ano_ant, tri_ant);
    if lag_map.isKey(key)
        omega_lag_idx(idx) = double(lag_map(key));
    end
end

valid_markov  = ~isnan(omega_lag_idx);
n_valid_markov = sum(valid_markov);

% =========================================================================
% 4. PRÉ-COMPUTAR LAGS MÚLTIPLOS DE V E K (instrumentos: 5 lags)
% =========================================================================

log_v_lags = NaN(n_obs, n_lags);
log_k_lag1 = NaN(n_obs, 1);

for idx = 1:n_obs
    ano_j = anos(idx);
    tri_j = trimestres(idx);
    
    for j = 1:n_lags
        [ano_prev, tri_prev] = prev_quarter(ano_j, tri_j);
        key = sprintf('%d_%d_%d', emp_ids(idx), ano_prev, tri_prev);
        
        if lag_map.isKey(key)
            lag_idx = double(lag_map(key));
            log_v_lags(idx, j) = log_v(lag_idx);
            if j == 1
                log_k_lag1(idx) = log_k(lag_idx);
            end
        else
            break   % gap → lags de ordem > j também serão NaN
        end
        
        ano_j = ano_prev;
        tri_j = tri_prev;
    end
end

% =========================================================================
% 5. MÁSCARA DE VALIDADE PARA MOMENTOS
%
% Obs válida para momentos: lag de ω existe (para ξ) E pelo menos os
% 2 primeiros lags de V existem E K_{t-1} existe.
% (O conjunto parcimonioso usa v_{t-1} e v_{t-2}; o full usa todos.)
% =========================================================================

n_lags_required = min(n_lags, 2);  % parcimonioso precisa de 2 lags
valid_moments = valid_markov & ~isnan(log_k_lag1) & ...
                all(~isnan(log_v_lags(:, 1:n_lags_required)), 2);
n_valid_moments = sum(valid_moments);

if n_valid_moments < 20
    warning('precompute_lags: apenas %d obs válidas para momentos.', n_valid_moments);
end

% =========================================================================
% 6. PRÉ-COMPUTAR MATRIZ DE INSTRUMENTOS Z
%
% Dois conjuntos disponíveis:
%
% 'full' (18 instrumentos — consistente com 2SLS):
%   k_it, k_it², k_{it-1}, V_{t-1}...V_{t-L},
%   V_{t-1}²...V_{t-L}², V_{t-j}·k_it para j=1...L
%
% 'parsimonious' (6 instrumentos — recomendado para two-step):
%   k_it, k_{it-1}, v_{it-1}, v_{it-2}, v_{it-1}², v_{it-1}·k_it
%
% O conjunto parcimonioso é preferível para o GMM two-step porque:
%   - Reduz viés de muitos instrumentos em amostras finitas
%   - Melhora condicionamento de Ω̂ (menos ruído na construção de Ŵ)
%   - Mantém sobre-identificação (6-5=1 g.l.) para o teste J
%   - Alinhado com a prática da literatura ACF
%
% Seleção via campo instrument_set (default: detecta automaticamente)
% =========================================================================

log_k_vm   = log_k(valid_moments);
log_kl_vm  = log_k_lag1(valid_moments);
log_vl_vm  = log_v_lags(valid_moments, :);

% Determinar conjunto de instrumentos
if n_lags >= 2
    % Conjunto parcimonioso (default): 6 instrumentos
    Z = [log_k_vm, ...            % k_it
         log_kl_vm, ...           % k_{it-1}
         log_vl_vm(:,1), ...      % v_{it-1}
         log_vl_vm(:,2), ...      % v_{it-2}
         log_vl_vm(:,1).^2, ...   % v_{it-1}²
         log_vl_vm(:,1) .* log_k_vm];  % v_{it-1} · k_it
else
    % Fallback minimal: 4 instrumentos
    Z = [log_k_vm, log_kl_vm, log_vl_vm(:,1), log_vl_vm(:,1).^2];
end

% SEM normalização — instrumentos em escala natural.
% A normalização distorce a interpretação dos momentos e pode criar
% incompatibilidades artificiais entre condições de momento.
% A matriz Ŵ do two-step pondera otimamente pela variância.

% =========================================================================
% 7. EMPACOTAR RESULTADO
% =========================================================================

precomp = struct();

% Vetores originais
precomp.log_q     = log_q;
precomp.log_v     = log_v;
precomp.log_k     = log_k;
precomp.n_obs     = n_obs;

% Markov (compute_innovation)
precomp.omega_lag_idx   = omega_lag_idx;
precomp.valid_markov    = valid_markov;
precomp.n_valid_markov  = n_valid_markov;

% Momentos (compute_moments)
precomp.log_v_lags       = log_v_lags;
precomp.log_k_lag1       = log_k_lag1;
precomp.valid_moments    = valid_moments;
precomp.n_valid_moments  = n_valid_moments;

% Instrumentos pré-computados
precomp.Z          = Z;
precomp.n_moments  = size(Z, 2);
precomp.n_lags     = n_lags;

end


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
