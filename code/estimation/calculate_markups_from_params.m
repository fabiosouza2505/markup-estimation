function [markups, elasticities, stats] = calculate_markups_from_params(data, params, config)
    %CALCULATE_MARKUPS_FROM_PARAMS Calcula markups a partir dos parâmetros
    %
    % Elasticidade do insumo variável (para cada observação i):
    % θ_v(i) = β_v + β_vv·log(v_i) + β_vk·log(k_i)
    %
    % Markup: μ_i = θ_v(i) / α_v(i)
    % onde α_v(i) = share do insumo variável na receita
    %
    % Inputs:
    %   data - Tabela com dados
    %   params - Parâmetros estimados
    %   config - Configurações (max_markup)
    %
    % Outputs:
    %   markups - Vetor de markups (um por observação)
    %   elasticities - Elasticidades calculadas
    %   stats - Estatísticas dos markups
    
    % Extrair variáveis
    log_v = data.log_variable_input;
    log_k = data.log_capital;
    alpha_v = data.share_variable_input;
    
    % =====================================================================
    % CALCULAR ELASTICIDADES
    % =====================================================================
    
    % Elasticidade do insumo variável (varia por observação)
    % θ_v = ∂log(Q)/∂log(V) = β_v + β_vv·log(V) + β_vk·log(K)
    theta_v_obs = params.beta_v + ...
                  params.beta_vv .* log_v + ...
                  params.beta_vk .* log_k;
    
    % Elasticidade do capital (varia por observação)
    % θ_k = ∂log(Q)/∂log(K) = β_k + β_kk·log(K) + β_vk·log(V)
    theta_k_obs = params.beta_k + ...
                  params.beta_kk .* log_k + ...
                  params.beta_vk .* log_v;
    
    % =====================================================================
    % CALCULAR MARKUPS
    % =====================================================================
    
    % Markup = Elasticidade / Share
    % μ_i = θ_v(i) / α_v(i)
    markups = theta_v_obs ./ alpha_v;
    
    % =====================================================================
    % FILTRAR VALORES INVÁLIDOS
    % =====================================================================
    
    % Remover markups negativos
    markups(markups < 0) = NaN;
    
    % Remover markups muito altos (outliers)
    if isfield(config, 'max_markup')
        markups(markups > config.max_markup) = NaN;
    end
    
    % Remover infinitos
    markups(isinf(markups)) = NaN;
    
    % =====================================================================
    % ELASTICIDADES (médias e individuais)
    % =====================================================================
    
    elasticities = struct();
    elasticities.theta_v_mean = nanmean(theta_v_obs);
    elasticities.theta_k_mean = nanmean(theta_k_obs);
    elasticities.theta_v_obs = theta_v_obs;
    elasticities.theta_k_obs = theta_k_obs;
    
    % Erros-padrão (aproximação simples)
    elasticities.theta_v_se = nanstd(theta_v_obs) / sqrt(sum(~isnan(theta_v_obs)));
    elasticities.theta_k_se = nanstd(theta_k_obs) / sqrt(sum(~isnan(theta_k_obs)));
    
    % =====================================================================
    % ESTATÍSTICAS DOS MARKUPS
    % =====================================================================
    
    markups_valid = markups(~isnan(markups));
    
    stats = struct();
    stats.mean = nanmean(markups);
    stats.median = nanmedian(markups);
    stats.std = nanstd(markups);
    stats.min = min(markups_valid);
    stats.max = max(markups_valid);
    stats.p25 = prctile(markups_valid, 25);
    stats.p75 = prctile(markups_valid, 75);
    stats.n_valid = sum(~isnan(markups));
    stats.n_invalid = sum(isnan(markups));
    stats.pct_above_1 = sum(markups_valid > 1) / length(markups_valid);
end