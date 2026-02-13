function save_multiple_sectors_results(results_all, output_dir)
    %SAVE_MULTIPLE_SECTORS_RESULTS Salva resultados de múltiplos setores
    %
    % Gera arquivos equivalentes aos outputs do Python:
    %   1. translog_parametros.csv      (save_translog_parameters)
    %   2. markup_sumario.csv           (save_markup_summary)
    %   3. diagnosticos.csv             (save_diagnostic_results)
    %
    % INPUTS:
    %   results_all - Struct com campos:
    %                 • setores (cell array de nomes)
    %                 • params (cell array de structs)
    %                 • diagnostics (cell array de structs)
    %                 • markup_stats (cell array de structs)
    %   output_dir  - Diretório de saída
    %
    % Autor: Fabio de Medeiros Souza
    % Data: Fevereiro 2025
    
    n_setores = length(results_all.setores);
    
    if n_setores == 0
        warning('Nenhum setor para salvar.');
        return;
    end
    
    % Criar diretório se não existir
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % =====================================================================
    % 1. PARÂMETROS TRANSLOG (equivale a save_translog_parameters do Python)
    % =====================================================================
    
    try
        params_table = table();
        params_table.setor      = results_all.setores(:);  % (:) força coluna
        params_table.beta0      = cellfun(@(x) x.beta0, results_all.params(:));
        params_table.beta_k     = cellfun(@(x) x.beta_k, results_all.params(:));
        params_table.beta_kk    = cellfun(@(x) x.beta_kk, results_all.params(:));
        params_table.beta_omega = cellfun(@(x) x.beta_omega, results_all.params(:));
        params_table.beta_v     = cellfun(@(x) x.beta_v, results_all.params(:));
        params_table.beta_vv    = cellfun(@(x) x.beta_vv, results_all.params(:));
        params_table.beta_vk    = cellfun(@(x) x.beta_vk, results_all.params(:));
        
        params_file = fullfile(output_dir, 'translog_parametros.csv');
        writetable(params_table, params_file);
        fprintf('  ✓ Parâmetros translog: %s\n', params_file);
        
    catch ME
        warning('Erro ao salvar parâmetros: %s', ME.message);
    end
    
    % =====================================================================
    % 2. RESUMO DE MARKUPS (equivale a save_markup_summary do Python)
    % =====================================================================
    
    try
        markups_table = table();
        markups_table.setor          = results_all.setores(:);
        markups_table.mean_weighted  = cellfun(@(x) x.mean, results_all.markup_stats(:));
        markups_table.mean_simple    = cellfun(@(x) safe_field(x, 'mean_simple', NaN), results_all.markup_stats(:));
        markups_table.median         = cellfun(@(x) x.median, results_all.markup_stats(:));
        markups_table.std            = cellfun(@(x) x.std, results_all.markup_stats(:));
        markups_table.min            = cellfun(@(x) x.min, results_all.markup_stats(:));
        markups_table.max            = cellfun(@(x) x.max, results_all.markup_stats(:));
        markups_table.p25            = cellfun(@(x) safe_field(x, 'p25', NaN), results_all.markup_stats(:));
        markups_table.p75            = cellfun(@(x) safe_field(x, 'p75', NaN), results_all.markup_stats(:));
        markups_table.pct_above_1    = cellfun(@(x) safe_field(x, 'pct_above_1', NaN), results_all.markup_stats(:));
        markups_table.n_valid        = cellfun(@(x) safe_field(x, 'n_valid', NaN), results_all.markup_stats(:));
        
        markups_file = fullfile(output_dir, 'markup_sumario.csv');
        writetable(markups_table, markups_file);
        fprintf('  ✓ Resumo de markups: %s\n', markups_file);
        
    catch ME
        warning('Erro ao salvar markups: %s', ME.message);
    end
    
    % =====================================================================
    % 3. DIAGNÓSTICOS (equivale a save_diagnostic_results do Python)
    % =====================================================================
    
    try
        diag_table = table();
        diag_table.setor              = results_all.setores(:);
        diag_table.method             = repmat({'2SLS'}, n_setores, 1);
        diag_table.reduced_form_r2    = cellfun(@(x) safe_field(x, 'reduced_form_r2', NaN), results_all.diagnostics(:));
        diag_table.rsquared_2sls      = cellfun(@(x) x.rsquared, results_all.diagnostics(:));
        diag_table.rmse               = cellfun(@(x) x.rmse, results_all.diagnostics(:));
        diag_table.f_stat_mean        = cellfun(@(x) safe_field(x, 'f_stat_mean', NaN), results_all.diagnostics(:));
        diag_table.weak_instruments   = cellfun(@(x) safe_field(x, 'weak_instruments', NaN), results_all.diagnostics(:));
        diag_table.n_obs              = cellfun(@(x) safe_field(x, 'n_obs', NaN), results_all.diagnostics(:));
        diag_table.n_instruments      = cellfun(@(x) safe_field(x, 'n_instruments', NaN), results_all.diagnostics(:));
        diag_table.omega_mean         = cellfun(@(x) safe_field(x, 'omega_mean', NaN), results_all.diagnostics(:));
        diag_table.omega_std          = cellfun(@(x) safe_field(x, 'omega_std', NaN), results_all.diagnostics(:));
        
        diag_file = fullfile(output_dir, 'diagnosticos.csv');
        writetable(diag_table, diag_file);
        fprintf('  ✓ Diagnósticos: %s\n', diag_file);
        
    catch ME
        warning('Erro ao salvar diagnósticos: %s', ME.message);
    end
    
    % =====================================================================
    % RESUMO FINAL
    % =====================================================================
    
    fprintf('  ✓ Resumo de %d setores salvo em %s\n', n_setores, output_dir);
    
end


% =========================================================================
% FUNÇÃO AUXILIAR: Acesso seguro a campos de struct
% =========================================================================
function val = safe_field(s, field_name, default_val)
    %SAFE_FIELD Retorna valor do campo se existir, senão retorna default
    if isfield(s, field_name)
        val = s.(field_name);
    else
        val = default_val;
    end
end
