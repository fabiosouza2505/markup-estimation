function save_estimation_results(results_all, output_dir)
    %SAVE_ESTIMATION_RESULTS Salva markups a nível de empresa/período
    %
    % Equivale ao método save_estimation_results do Python.
    % Gera um CSV consolidado com markup por firma-período para todos os setores.
    %
    % INPUTS:
    %   results_all - Struct com campos:
    %                 • setores      (cell array de nomes)
    %                 • params       (cell array de structs)
    %                 • diagnostics  (cell array de structs)
    %                 • markup_stats (cell array de structs)
    %                 • markups_raw  (cell array de vetores de markup)
    %                 • elasticities_raw (cell array de structs com theta_v, theta_k)
    %                 • sector_data  (cell array de tables com dados do setor)
    %   output_dir  - Diretório de saída
    %
    % OUTPUT:
    %   Arquivo: markups_empresa.csv
    %   Colunas: setor_codigo, setor_nome, empresa, ano, trimestre,
    %            markup, theta_v, theta_k, share_v, log_v, log_k
    %
    % REFERÊNCIA:
    %   Equivalente Python: TranslogMarkupEstimator.save_estimation_results()
    %
    % Autor: Fabio de Medeiros Souza
    % Data: Fevereiro 2025
    
    n_setores = length(results_all.setores);
    
    if n_setores == 0
        warning('Nenhum setor para salvar.');
        return;
    end
    
    % Verificar se campos necessários existem
    if ~isfield(results_all, 'markups_raw') || ~isfield(results_all, 'sector_data')
        warning(['Campos markups_raw e/ou sector_data não encontrados em results_all. ' ...
                 'Verifique se main.m armazena esses campos durante o loop de estimação.']);
        return;
    end
    
    % Criar diretório se não existir
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % =====================================================================
    % CONSOLIDAR DADOS DE TODOS OS SETORES
    % =====================================================================
    
    % Pré-alocar cell arrays (um elemento por setor, concatenar no final)
    chunks_setor_codigo = cell(n_setores, 1);
    chunks_setor_nome   = cell(n_setores, 1);
    chunks_empresa      = cell(n_setores, 1);
    chunks_ano          = cell(n_setores, 1);
    chunks_trimestre    = cell(n_setores, 1);
    chunks_markup       = cell(n_setores, 1);
    chunks_theta_v      = cell(n_setores, 1);
    chunks_theta_k      = cell(n_setores, 1);
    chunks_share_v      = cell(n_setores, 1);
    chunks_log_v        = cell(n_setores, 1);
    chunks_log_k        = cell(n_setores, 1);
    valid_sectors = false(n_setores, 1);
    
    for i = 1:n_setores
        try
            % Extrair dados do setor
            sector_name = results_all.setores{i};
            markups     = results_all.markups_raw{i};
            elast       = results_all.elasticities_raw{i};
            sdata       = results_all.sector_data{i};
            
            n_obs = length(markups);
            
            if n_obs == 0
                continue;
            end
            
            % Extrair identificadores do setor
            if ismember('setor_ipa_7d', sdata.Properties.VariableNames)
                setor_codigo = repmat({num2str(sdata.setor_ipa_7d(1))}, n_obs, 1);
            else
                setor_codigo = repmat({sector_name}, n_obs, 1);
            end
            
            setor_nome = repmat({sector_name}, n_obs, 1);
            
            % Extrair empresa (pode ser cell, string ou numérico)
            if ismember('empresa', sdata.Properties.VariableNames)
                empresa_raw = sdata.empresa;
                if iscell(empresa_raw)
                    empresa = empresa_raw(1:n_obs);
                elseif isstring(empresa_raw)
                    empresa = cellstr(empresa_raw(1:n_obs));
                else
                    empresa = arrayfun(@num2str, empresa_raw(1:n_obs), 'UniformOutput', false);
                end
            else
                empresa = repmat({''}, n_obs, 1);
            end
            
            % Extrair ano
            if ismember('ano', sdata.Properties.VariableNames)
                ano = sdata.ano(1:n_obs);
            else
                ano = NaN(n_obs, 1);
            end
            
            % Extrair trimestre
            if ismember('trimestre', sdata.Properties.VariableNames)
                trimestre = sdata.trimestre(1:n_obs);
            else
                trimestre = NaN(n_obs, 1);
            end
            
            % Extrair elasticidades por firma (se disponíveis)
            if isfield(elast, 'theta_v') && length(elast.theta_v) >= n_obs
                theta_v = elast.theta_v(1:n_obs);
            else
                theta_v = NaN(n_obs, 1);
            end
            
            if isfield(elast, 'theta_k') && length(elast.theta_k) >= n_obs
                theta_k = elast.theta_k(1:n_obs);
            else
                theta_k = NaN(n_obs, 1);
            end
            
            % Extrair share e inputs
            if ismember('share_variable_input', sdata.Properties.VariableNames)
                share_v = sdata.share_variable_input(1:n_obs);
            else
                share_v = NaN(n_obs, 1);
            end
            
            if ismember('log_variable_input', sdata.Properties.VariableNames)
                log_v = sdata.log_variable_input(1:n_obs);
            else
                log_v = NaN(n_obs, 1);
            end
            
            if ismember('log_capital', sdata.Properties.VariableNames)
                log_k = sdata.log_capital(1:n_obs);
            else
                log_k = NaN(n_obs, 1);
            end
            
            % Garantir que vetores numéricos são coluna
            markups = markups(:);
            theta_v = theta_v(:);
            theta_k = theta_k(:);
            share_v = share_v(:);
            log_v   = log_v(:);
            log_k   = log_k(:);
            ano     = ano(:);
            trimestre = trimestre(:);
            
            % Armazenar no slot pré-alocado (sem crescer arrays)
            chunks_setor_codigo{i} = setor_codigo;  
            chunks_setor_nome{i}   = setor_nome;    
            chunks_empresa{i}      = empresa;       
            chunks_ano{i}          = ano;           
            chunks_trimestre{i}    = trimestre;     
            chunks_markup{i}       = markups;       
            chunks_theta_v{i}      = theta_v;       
            chunks_theta_k{i}      = theta_k;       
            chunks_share_v{i}      = share_v;       
            chunks_log_v{i}        = log_v;         
            chunks_log_k{i}        = log_k;         
            valid_sectors(i) = true;
            
        catch ME
            warning('Erro processando setor %s: %s', results_all.setores{i}, ME.message);
        end
    end
    
    % =====================================================================
    % CONCATENAR CHUNKS (uma única operação, sem realocação incremental)
    % =====================================================================
    
    idx = valid_sectors;
    all_setor_codigo = vertcat(chunks_setor_codigo{idx});
    all_setor_nome   = vertcat(chunks_setor_nome{idx});
    all_empresa      = vertcat(chunks_empresa{idx});
    all_ano          = vertcat(chunks_ano{idx});
    all_trimestre    = vertcat(chunks_trimestre{idx});
    all_markup       = vertcat(chunks_markup{idx});
    all_theta_v      = vertcat(chunks_theta_v{idx});
    all_theta_k      = vertcat(chunks_theta_k{idx});
    all_share_v      = vertcat(chunks_share_v{idx});
    all_log_v        = vertcat(chunks_log_v{idx});
    all_log_k        = vertcat(chunks_log_k{idx});
    
    % =====================================================================
    % MONTAR E SALVAR TABELA
    % =====================================================================
    
    if isempty(all_markup)
        warning('Nenhum markup a nível de firma para salvar.');
        return;
    end
    
    % Criar tabela consolidada
    results_table = table();
    results_table.setor_codigo = all_setor_codigo;
    results_table.setor_nome   = all_setor_nome;
    results_table.empresa      = all_empresa;
    results_table.ano          = all_ano;
    results_table.trimestre    = all_trimestre;
    results_table.markup       = all_markup;
    results_table.theta_v      = all_theta_v;
    results_table.theta_k      = all_theta_k;
    results_table.share_v      = all_share_v;
    results_table.log_v        = all_log_v;
    results_table.log_k        = all_log_k;
    
    % Remover linhas com markup NaN
    valid_rows = ~isnan(results_table.markup);
    results_table = results_table(valid_rows, :);
    
    % Salvar CSV
    output_file = fullfile(output_dir, 'markups_empresa.csv');
    writetable(results_table, output_file);
    
    fprintf('  ✓ Markups por empresa: %s (%d observações)\n', ...
            output_file, height(results_table));
    
    % =====================================================================
    % GERAR MÉDIAS POR SETOR-PERÍODO (equivale a save_sector_period_markups)
    % =====================================================================
    
    try
        % Agrupar por setor e ano
        [groups, setor_g, ano_g] = findgroups(results_table.setor_nome, results_table.ano);
        
        mean_markup  = splitapply(@nanmean, results_table.markup, groups);
        std_markup   = splitapply(@nanstd, results_table.markup, groups);
        n_obs_g      = splitapply(@length, results_table.markup, groups);
        se_markup    = std_markup ./ sqrt(n_obs_g);
        
        % Intervalo de confiança 95%
        ci_lower = mean_markup - 1.96 * se_markup;
        ci_upper = mean_markup + 1.96 * se_markup;
        market_power = ci_lower > 1.0;
        
        % Montar tabela
        period_table = table();
        period_table.setor_nome    = setor_g;
        period_table.ano           = ano_g;
        period_table.markup_medio  = mean_markup;
        period_table.markup_se     = se_markup;
        period_table.markup_std    = std_markup;
        period_table.ci_lower      = ci_lower;
        period_table.ci_upper      = ci_upper;
        period_table.n_obs         = n_obs_g;
        period_table.market_power  = market_power;
        
        % Ordenar
        period_table = sortrows(period_table, {'setor_nome', 'ano'});
        
        % Salvar
        period_file = fullfile(output_dir, 'markups_setor_periodo.csv');
        writetable(period_table, period_file);
        
        fprintf('  ✓ Markups setor-período: %s (%d grupos)\n', ...
                period_file, height(period_table));
        
    catch ME
        warning('Erro ao gerar médias setor-período: %s', ME.message);
    end
    
end
