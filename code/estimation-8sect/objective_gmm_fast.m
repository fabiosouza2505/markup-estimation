function obj = objective_gmm_fast(theta, precomp, markov_degree, bounds, W)
%OBJECTIVE_GMM_FAST Função objetivo GMM-ACF vetorizada (1-step e 2-step)
%
% Suporta dois modos:
%   W = []  ou omitido → Q(β) = g(β)'·g(β)           (W = I, 1º passo)
%   W = M×M            → Q(β) = g(β)'·W·g(β)         (2º passo eficiente)
%
% O otimizador opera no espaço irrestrito θ ∈ ℝ⁵. Internamente:
%   β = lb + (ub − lb) · σ(θ)   onde σ(x) = 1/(1+exp(−x))
%
% INPUTS:
%   theta         - [θ₁,...,θ₅] espaço irrestrito (1×5)
%   precomp       - Struct de precompute_lags
%   markov_degree - Grau do polinômio de Markov (escalar)
%   bounds        - Struct com .lb (1×5) e .ub (1×5). [] = sem bounds
%   W             - Matriz de ponderação M×M. [] ou omitido = identidade
%
% OUTPUT:
%   obj - Q(β) = g(β)'·W·g(β)
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

% =========================================================================
% TRANSFORMAÇÃO: θ irrestrito → β com bounds
% =========================================================================

if nargin >= 4 && ~isempty(bounds)
    sigmoid = 1 ./ (1 + exp(-theta));
    beta = bounds.lb + (bounds.ub - bounds.lb) .* sigmoid;
else
    beta = theta;
end

% =========================================================================
% ESTÁGIO 1: Φ(β) = log(Q) - f(V,K;β)  [vetorial]
% =========================================================================

phi = precomp.log_q - (beta(1) .* precomp.log_v       + ...
                       beta(2) .* precomp.log_k       + ...
                       beta(3) .* precomp.log_v.^2    + ...
                       beta(4) .* precomp.log_k.^2    + ...
                       beta(5) .* precomp.log_v .* precomp.log_k);

% =========================================================================
% ESTÁGIO 2: Processo de Markov → ξ(β)
% =========================================================================

omega = phi;

valid_mk   = precomp.valid_markov;
omega_curr = omega(valid_mk);
omega_prev = omega(precomp.omega_lag_idx(valid_mk));

n_valid_mk = precomp.n_valid_markov;
p          = markov_degree;

% [1, ω_{t-1}, ω_{t-1}², ..., ω_{t-1}^p]
X_mk = ones(n_valid_mk, p + 1);
for j = 1:p
    X_mk(:, j+1) = omega_prev .^ j;
end

% OLS → resíduos = inovação ξ
xi_mk = omega_curr - X_mk * (X_mk \ omega_curr);

% =========================================================================
% ESTÁGIO 3: Condições de momento g(β) = (1/N) Z' · ξ
% =========================================================================

xi_full = NaN(precomp.n_obs, 1);
xi_full(valid_mk) = xi_mk;

xi_mom = xi_full(precomp.valid_moments);

if any(isnan(xi_mom))
    obj = 1e10;
    return
end

% g(β) = mean(Z .* ξ)   →   (M × 1)
g_mean = mean(precomp.Z .* xi_mom, 1)';

% =========================================================================
% CRITÉRIO GMM: Q(β) = g(β)' · W · g(β)
% =========================================================================

if nargin >= 5 && ~isempty(W)
    obj = g_mean' * W * g_mean;
else
    obj = g_mean' * g_mean;
end

if ~isfinite(obj)
    obj = 1e10;
end

end
