function phi = compute_phi(data, beta)
%COMPUTE_PHI Estágio 1 do GMM-ACF: recupera Φ(β) = log(Q) - f(V,K;β)
%
% Φᵢₜ(β) absorve a constante e a produtividade:
%   Φᵢₜ(β) = β₀ + ωᵢₜ(β)
%            = log(Qᵢₜ) - βᵥ·vᵢₜ - βₖ·kᵢₜ - β_vv·vᵢₜ² - β_kk·kᵢₜ² - β_vk·vᵢₜ·kᵢₜ
%
% A constante β₀ será absorvida na constante da regressão de Markov
% no Estágio 2, portanto não precisa ser separada aqui.
%
% INPUTS:
%   data   - Tabela com variáveis:
%              log_q  : log do produto (valor adicionado ou receita)
%              log_v  : log do insumo variável
%              log_k  : log do capital
%   beta   - Vetor [β_v, β_k, β_vv, β_kk, β_vk] (5 × 1)
%            Nota: β₀ não entra aqui — é absorvido pelo Markov
%
% OUTPUTS:
%   phi    - Vetor (N × 1) com Φᵢₜ(β) para cada observação
%
% REFERÊNCIA:
%   Ackerberg, Caves & Frazer (2015), Econometrica, Sec. 3-4
%   De Loecker & Warzynski (2012), AER, 102(6)
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

% =========================================================================
% VALIDAÇÃO DE INPUTS
% =========================================================================

required_vars = {'log_q', 'log_v', 'log_k'};
for i = 1:length(required_vars)
    if ~ismember(required_vars{i}, data.Properties.VariableNames)
        error('compute_phi: variável ''%s'' não encontrada nos dados.', required_vars{i});
    end
end

if numel(beta) ~= 5
    error('compute_phi: beta deve ter 5 elementos [β_v, β_k, β_vv, β_kk, β_vk].');
end

% =========================================================================
% EXTRAÇÃO DE VARIÁVEIS
% =========================================================================

log_q = data.log_q;
log_v = data.log_v;
log_k = data.log_k;

beta_v  = beta(1);
beta_k  = beta(2);
beta_vv = beta(3);
beta_kk = beta(4);
beta_vk = beta(5);

% =========================================================================
% CÁLCULO DE Φ(β)
%
% Translog sem constante (β₀ vai para o Markov):
%   f(V,K;β) = β_v·V + β_k·K + β_vv·V² + β_kk·K² + β_vk·V·K
%
% Φ(β) = log(Q) - f(V,K;β)
% =========================================================================

f_translog = beta_v  .* log_v       + ...
             beta_k  .* log_k       + ...
             beta_vv .* log_v.^2    + ...
             beta_kk .* log_k.^2    + ...
             beta_vk .* log_v .* log_k;

phi = log_q - f_translog;

end
