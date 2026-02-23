function [xi, omega, omega_lag] = compute_innovation(data, phi, config)
%COMPUTE_INNOVATION Estágio 2 do GMM-ACF: processo de Markov e inovação ξ(β)
%
% Estima o processo AR(1) não-paramétrico de produtividade:
%   ωᵢₜ = g(ωᵢₜ₋₁) + ξᵢₜ
%
% onde g(·) é aproximado por polinômio de ordem p em ωᵢₜ₋₁.
% A inovação ξᵢₜ é o resíduo desta regressão.
%
% Como Φᵢₜ = β₀ + ωᵢₜ, a constante β₀ é absorvida pelo intercepto
% da regressão de Markov, portanto:
%   ωᵢₜ ≈ Φᵢₜ (a menos de β₀, que cancela na regressão)
%
% ATENÇÃO: lags respeitam fronteiras de firma — observações onde
% o lag pertence a outra firma recebem NaN e são excluídas.
%
% PERFORMANCE: usa containers.Map (via build_lag_map) para lookup O(1),
% reduzindo complexidade total de O(N²) para O(N).
%
% INPUTS:
%   data    - Tabela com variáveis:
%               empresa : identificador de firma
%               ano     : período
%               (trimestre : opcional, default = lag anual)
%   phi     - Vetor (N × 1) com Φᵢₜ(β) do Estágio 1
%   config  - Struct com campos opcionais:
%               markov_degree : grau do polinômio (default: 3)
%               verbose       : exibir diagnósticos (default: false)
%               lag_map       : containers.Map pré-construído (opcional)
%                               Se fornecido, evita reconstrução a cada chamada.
%
% OUTPUTS:
%   xi        - Vetor (N × 1) com inovação ξᵢₜ(β); NaN nas obs sem lag
%   omega     - Vetor (N × 1) com ωᵢₜ = Φᵢₜ (proxy de produtividade)
%   omega_lag - Vetor (N × 1) com ωᵢₜ₋₁ respeitando fronteiras de firma
%
% REFERÊNCIA:
%   Ackerberg, Caves & Frazer (2015), Econometrica, Eq. (11)-(13)
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

% =========================================================================
% CONFIGURAÇÃO
% =========================================================================

if nargin < 3 || isempty(config)
    config = struct();
end
if ~isfield(config, 'markov_degree'), config.markov_degree = 3;  end
if ~isfield(config, 'verbose'),       config.verbose       = false; end

p = config.markov_degree;

% =========================================================================
% VALIDAÇÃO
% =========================================================================

required_vars = {'empresa', 'ano'};
for i = 1:length(required_vars)
    if ~ismember(required_vars{i}, data.Properties.VariableNames)
        error('compute_innovation: variável ''%s'' não encontrada.', required_vars{i});
    end
end

n_obs = height(data);
if numel(phi) ~= n_obs
    error('compute_innovation: phi deve ter o mesmo número de linhas que data.');
end

% =========================================================================
% OMEGA = PHI (produtividade proxy, a menos de β₀)
% =========================================================================

omega = phi;

% =========================================================================
% LAG DE OMEGA RESPEITANDO FRONTEIRAS DE FIRMA (via containers.Map)
%
% Para cada observação (i,t), busca a observação (i,t-1) da MESMA firma.
% Se não existir (primeira obs da firma ou gap no painel), recebe NaN.
%
% Complexidade: O(N) com build_lag_map, vs O(N²) com busca por máscara.
% =========================================================================

% Construir ou reutilizar mapa de lookup
if isfield(config, 'lag_map') && ~isempty(config.lag_map)
    lag_map = config.lag_map;
else
    lag_map = build_lag_map(data);
end

anos       = data.ano;
trimestres = get_trimestre(data);
empresa_ids = normalize_empresa_ids(data.empresa);

omega_lag = NaN(n_obs, 1);

for idx = 1:n_obs
    [ano_ant, tri_ant] = prev_quarter(anos(idx), trimestres(idx));
    key = sprintf('%d_%d_%d', empresa_ids(idx), ano_ant, tri_ant);
    
    if lag_map.isKey(key)
        omega_lag(idx) = omega(double(lag_map(key)));
    end
end

% =========================================================================
% REGRESSÃO DE MARKOV: ωᵢₜ = g(ωᵢₜ₋₁) + ξᵢₜ
%
% Estimação por OLS de polinômio de grau p em ωᵢₜ₋₁
% Usando apenas observações com lag válido
% =========================================================================

valid = ~isnan(omega_lag);
n_valid = sum(valid);

if n_valid < (p + 2)
    error('compute_innovation: observações insuficientes para Markov de grau %d (%d válidas).', p, n_valid);
end

omega_curr = omega(valid);
omega_prev = omega_lag(valid);

% Monta matriz de regressão [1, ω_{t-1}, ω_{t-1}², ..., ω_{t-1}^p]
X_markov = ones(n_valid, p + 1);
for j = 1:p
    X_markov(:, j+1) = omega_prev .^ j;
end

% OLS
coef_markov = X_markov \ omega_curr;

% Resíduos = inovação de produtividade
omega_hat_markov = X_markov * coef_markov;
xi_valid         = omega_curr - omega_hat_markov;

% =========================================================================
% MONTAR VETOR COMPLETO DE xi (NaN onde não há lag)
% =========================================================================

xi = NaN(n_obs, 1);
xi(valid) = xi_valid;

% =========================================================================
% DIAGNÓSTICOS (opcional)
% =========================================================================

if config.verbose
    SS_res = sum(xi_valid.^2);
    SS_tot = sum((omega_curr - mean(omega_curr)).^2);
    r2_markov = 1 - SS_res / SS_tot;
    
    fprintf('   [Markov] grau=%d | n_válido=%d | R²=%.4f | std(ξ)=%.4f\n', ...
        p, n_valid, r2_markov, std(xi_valid));
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
        warning('compute_innovation: coluna ''trimestre'' não encontrada. Usando lag anual.');
    end
end
