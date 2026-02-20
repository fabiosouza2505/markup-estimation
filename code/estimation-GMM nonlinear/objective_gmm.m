function obj = objective_gmm(beta, data, config)
%OBJECTIVE_GMM Função objetivo do GMM-ACF com W = I para fminsearch
%
% Calcula o critério GMM:
%   Q(β) = g(β)' · g(β)   [W = I]
%
% Esta função encapsula os três estágios do ACF:
%   1. compute_phi        → Φᵢₜ(β)
%   2. compute_innovation → ξᵢₜ(β) via Markov
%   3. compute_moments    → g(β)  [18 instrumentos]
%
% PERFORMANCE: config.lag_map (containers.Map) é passado diretamente
% para compute_innovation e compute_moments, evitando reconstrução
% do mapa a cada avaliação.
%
% INPUTS:
%   beta   - Vetor (5 × 1): [β_v, β_k, β_vv, β_kk, β_vk]
%   data   - Tabela com dados preparados do setor
%   config - Struct com: markov_degree, n_lags, lag_map, etc.
%
% OUTPUT:
%   obj    - Escalar: Q(β) = g(β)'·g(β)
%
% REFERÊNCIA:
%   Ackerberg, Caves & Frazer (2015), Econometrica
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

% =========================================================================
% CONFIGURAÇÃO SILENCIOSA (objetivo é chamado muitas vezes)
% =========================================================================

config_inner = config;
config_inner.verbose = false;

% =========================================================================
% ESTÁGIO 1: Φ(β)
% =========================================================================

try
    phi = compute_phi(data, beta);
catch
    obj = 1e10;
    return
end

% =========================================================================
% ESTÁGIO 2: Inovação ξ(β)
% =========================================================================

try
    xi = compute_innovation(data, phi, config_inner);
catch
    obj = 1e10;
    return
end

% =========================================================================
% ESTÁGIO 3: Momentos g(β) — 18 instrumentos
% =========================================================================

try
    g_mean = compute_moments(data, xi, config_inner);
catch
    obj = 1e10;
    return
end

% =========================================================================
% CRITÉRIO GMM: Q(β) = g(β)'·g(β)
% =========================================================================

obj = g_mean' * g_mean;

% Verificação de sanidade
if ~isfinite(obj)
    obj = 1e10;
end

end
