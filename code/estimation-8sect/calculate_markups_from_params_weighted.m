function [markups, elasticities, markup_stats] = calculate_markups_from_params_weighted(data, params, diagnostics, config)
    % SINTAXE:
    %   [markups, elasticities, markup_stats] = ...
    %       calculate_markups_from_params_weighted(data, params, diagnostics, config)
    %
    % INPUTS:
    %   data        - Tabela com dados preparados (deve conter):
    %                 • log_variable_input, log_capital
    %                 • share_variable_input
    %                 • receita (para ponderação)
    %   params      - Struct com parâmetros estimados:
    %                 • beta_v, beta_k, beta_vv, beta_kk, beta_vk
    %   diagnostics - Struct com diagnósticos (NOVO - opcional):
    %                 • residuals (para correção de produtividade)
    %   config      - Struct com configurações (opcional):
    %                 • verbose (bool): Exibir mensagens
    %                 • max_markup (double): Markup máximo válido
    %                 • apply_productivity_correction (bool): Usar ω
    %                 • show_comparison (bool): Comparar com/sem correções
    %
    % OUTPUTS:
    %   markups      - Vetor de markups (n×1)
    %   elasticities - Struct com elasticidades
    %   markup_stats - Struct com estatísticas (ponderadas)
    %
    % EXEMPLO:
    %   config.apply_productivity_correction = true;
    %   config.max_markup = 10;
    %   [mu, elast, stats] = calculate_markups_from_params_weighted(...
    %       data_prep, params, diagnostics, config);
    %
    % REFERÊNCIA:
    %   De Loecker, J., & Warzynski, F. (2012). Markups and firm-level 
    %   export status. American Economic Review, 102(6), 2437-2471.
    %
    % Autor: Sistema de Estimação de Markups
    % Data: Fevereiro 2025
    
    %% =========================================================================
    % CONFIGURAÇÕES
    %% =========================================================================
    
    % Parâmetros default
    if nargin < 4
        config = struct();
    end
    if nargin < 3
        diagnostics = struct();
    end
    
    if ~isfield(config, 'verbose')
        config.verbose = true;
    end
    if ~isfield(config, 'max_markup')
        config.max_markup = 10;
    end
    if ~isfield(config, 'apply_productivity_correction')
        config.apply_productivity_correction = true;
    end
    if ~isfield(config, 'show_comparison')
        config.show_comparison = false;
    end
    
    if config.verbose
        fprintf('─────────────────────────────────────────\n');
        fprintf('CALCULANDO MARKUPS (VERSÃO CORRIGIDA)\n');
        fprintf('─────────────────────────────────────────\n\n');
    end
    
    %% =========================================================================
    % EXTRAIR DADOS
    %% =========================================================================
    
    log_v = data.log_variable_input;
    log_k = data.log_capital;
    alpha_v = data.share_variable_input;
    
    n = length(log_v);
    
    if config.verbose
        fprintf('Observações: %d\n', n);
    end
    
    %% =========================================================================
    % CALCULAR ELASTICIDADES (COM CORREÇÃO "2×"!)
    %% =========================================================================
    
    if config.verbose
        fprintf('Calculando elasticidades...\n');
    end
    
    % ★★★ CORREÇÃO CRÍTICA: Adicionar "2×" nos termos quadráticos! ★★★
    %
    % ANTES (ERRADO):
    % theta_v = params.beta_v + params.beta_vv .* log_v + params.beta_vk .* log_k;
    %
    % AGORA (CORRETO):
    % θ_v = ∂log(Q)/∂log(V) = β_v + 2×β_vv×log(V) + β_vk×log(K)
    
    theta_v = params.beta_v + ...
              2 * params.beta_vv .* log_v + ...  % ← "2×" CRÍTICO!
              params.beta_vk .* log_k;
    
    % θ_k = ∂log(Q)/∂log(K) = β_k + 2×β_kk×log(K) + β_vk×log(V)
    theta_k = params.beta_k + ...
              2 * params.beta_kk .* log_k + ...  % ← "2×" aqui também!
              params.beta_vk .* log_v;
    
    % Elasticidades
    elasticities = struct();
    elasticities.theta_v = theta_v;
    elasticities.theta_k = theta_k;
    elasticities.theta_v_mean = mean(theta_v(~isnan(theta_v)));
    elasticities.theta_k_mean = mean(theta_k(~isnan(theta_k)));
    
    if config.verbose
        fprintf('  θ_v médio: %.4f\n', elasticities.theta_v_mean);
        fprintf('  θ_k médio: %.4f\n', elasticities.theta_k_mean);
    end
    
    %% =========================================================================
    % ESTIMAR PRODUTIVIDADE ω (se disponível)
    %% =========================================================================
    
    omega = [];
    has_productivity = false;
        
    if config.apply_productivity_correction && isstruct(diagnostics)
    
        % Priorizar omega_hat (produtividade da forma reduzida)
        if isfield(diagnostics, 'omega_hat') && ~isempty(diagnostics.omega_hat)
            omega = diagnostics.omega_hat;
        
            if config.verbose
                fprintf('  Usando produtividade da forma reduzida (omega_hat)\n');
            end
    
        % Fallback: usar resíduos do 2SLS (menos correto, mas funcional)
        elseif isfield(diagnostics, 'residuals') && ~isempty(diagnostics.residuals)
            omega = diagnostics.residuals;
        
            if config.verbose
                fprintf('  Usando resíduos do 2SLS como proxy de produtividade\n');
            end
        else
            omega = [];
        end

        % Ajustar tamanho se necessário
        if length(omega) ~= n
            if length(omega) < n
                omega = [zeros(n - length(omega), 1); omega];
            else
                omega = omega(1:n);
            end
        end
        
        has_productivity = true;
        
        if config.verbose
            fprintf('  ω médio: %.4f (σ = %.4f)\n', mean(omega), std(omega));
        end
    else
        if config.verbose && config.apply_productivity_correction
            fprintf('Correção de produtividade solicitada mas resíduos não disponíveis\n');
        end
    end
    
    %% =========================================================================
    % CALCULAR MARKUPS
    %% =========================================================================
    
    if config.verbose
        fprintf('Calculando markups...\n');
    end
    
    % Markup base: μ = θ_v / α_v
    markups_base = theta_v ./ alpha_v;
    
    % Aplicar correção de produtividade (se disponível)
    if has_productivity
        productivity_correction = exp(omega);
        markups = markups_base .* productivity_correction;
        
        if config.verbose
            fprintf('  ✓ Correção ω aplicada (fator médio: %.4f)\n', ...
                    mean(productivity_correction));
        end
    else
        markups = markups_base;
        
        if config.verbose
            fprintf('  Sem correção de produtividade\n');
        end
    end
    
    %% =========================================================================
    % FILTRAR OUTLIERS
    %% =========================================================================
    
    if config.verbose
        fprintf('Filtrando outliers...\n');
    end
    
    n_original = length(markups);
    
    % Filtros
    markups(markups < 0.5) = NaN;
    markups(markups > config.max_markup) = NaN;
    markups(isnan(alpha_v)) = NaN;
    markups(alpha_v <= 0) = NaN;
    
    valid_idx = ~isnan(markups);
    n_valid = sum(valid_idx);
    n_removed = n_original - n_valid;
    
    if config.verbose
        fprintf('  Removidos: %d outliers (%.1f%%)\n', ...
                n_removed, (n_removed/n_original)*100);
        fprintf('  Válidos: %d markups\n', n_valid);
    end
    
    %% =========================================================================
    % CALCULAR ESTATÍSTICAS PONDERADAS POR RECEITA
    %% =========================================================================
    
    if config.verbose
        fprintf('Calculando estatísticas ponderadas...\n');
    end
    
    markups_valid = markups(valid_idx);
    
    % Extrair receita para ponderação
    if ismember('receita', data.Properties.VariableNames)
        receita = data.receita;
        receita_valid = receita(valid_idx);
    else
        receita_valid = ones(sum(valid_idx), 1);
        if config.verbose
            fprintf('  ⚠️  Receita não encontrada - usando pesos iguais\n');
        end
    end
    
    % Estatísticas
    markup_stats = struct();
    
    if isempty(markups_valid)
        % Sem markups válidos
        markup_stats.mean = NaN;
        markup_stats.mean_weighted = NaN;
        markup_stats.mean_simple = NaN;
        markup_stats.median = NaN;
        markup_stats.median_weighted = NaN;
        markup_stats.std = NaN;
        markup_stats.min = NaN;
        markup_stats.max = NaN;
        markup_stats.p25 = NaN;
        markup_stats.p75 = NaN;
        markup_stats.pct_above_1 = NaN;
        markup_stats.n_valid = 0;
        
        warning('Nenhum markup válido após filtragem!');
    else
        % ─────────────────────────────────────────────────────────────────
        % MÉDIA PONDERADA (PRINCIPAL - como Python)
        % ─────────────────────────────────────────────────────────────────
        markup_stats.mean_weighted = sum(markups_valid .* receita_valid) / ...
                                      sum(receita_valid);
        
        % Média simples (para comparação)
        markup_stats.mean_simple = mean(markups_valid);
        
        % Usar média ponderada como padrão
        markup_stats.mean = markup_stats.mean_weighted;
        
        % ─────────────────────────────────────────────────────────────────
        % MEDIANA PONDERADA (aproximação)
        % ─────────────────────────────────────────────────────────────────
        [sorted_mu, sort_idx] = sort(markups_valid);
        sorted_receita = receita_valid(sort_idx);
        cumsum_receita = cumsum(sorted_receita);
        total_receita = sum(sorted_receita);
        median_idx = find(cumsum_receita >= total_receita/2, 1);
        
        if ~isempty(median_idx)
            markup_stats.median_weighted = sorted_mu(median_idx);
        else
            markup_stats.median_weighted = NaN;
        end
        
        % ─────────────────────────────────────────────────────────────────
        % OUTRAS ESTATÍSTICAS (não ponderadas)
        % ─────────────────────────────────────────────────────────────────
        markup_stats.median = median(markups_valid);
        markup_stats.std = std(markups_valid);
        markup_stats.min = min(markups_valid);
        markup_stats.max = max(markups_valid);
        markup_stats.p25 = prctile(markups_valid, 25);
        markup_stats.p75 = prctile(markups_valid, 75);
        markup_stats.pct_above_1 = mean(markups_valid > 1);
        markup_stats.n_valid = length(markups_valid);
        
        if config.verbose
            fprintf('  Markup médio (ponderado): %.3f\n', markup_stats.mean_weighted);
            fprintf('  Markup médio (simples):   %.3f\n', markup_stats.mean_simple);
            fprintf('  Diferença ponderação: %.1f%%\n', ...
                    abs(markup_stats.mean_weighted - markup_stats.mean_simple) / ...
                    markup_stats.mean_simple * 100);
        end
    end
    
    %% =========================================================================
    % COMPARAÇÃO: COM vs SEM CORREÇÕES (se solicitado)
    %% =========================================================================
    
    if config.show_comparison && has_productivity && config.verbose
        fprintf('\n');
        fprintf('─────────────────────────────────────────\n');
        fprintf('COMPARAÇÃO: COM vs SEM CORREÇÕES\n');
        fprintf('─────────────────────────────────────────\n\n');
        
        % Recalcular sem correção ω
        markups_sem_omega = markups_base;
        markups_sem_omega(~valid_idx) = NaN;
        markups_sem_omega_valid = markups_sem_omega(valid_idx);
        
        mean_sem_omega = sum(markups_sem_omega_valid .* receita_valid) / ...
                         sum(receita_valid);
        mean_com_omega = markup_stats.mean_weighted;
        
        diff_omega_pct = ((mean_com_omega - mean_sem_omega) / mean_sem_omega) * 100;
        
        fprintf('SEM correção ω:  %.3f\n', mean_sem_omega);
        fprintf('COM correção ω:  %.3f\n', mean_com_omega);
        fprintf('Impacto ω:       %+.3f (%+.1f%%)\n\n', ...
                mean_com_omega - mean_sem_omega, diff_omega_pct);
    end
    
    if config.verbose
        fprintf('\n');
        fprintf('═════════════════════════════════════════\n');
        fprintf('CÁLCULO CONCLUÍDO\n');
        fprintf('═════════════════════════════════════════\n\n');
    end
    
end
