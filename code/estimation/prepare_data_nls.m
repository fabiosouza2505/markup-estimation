function [data_clean, stats] = prepare_data_nls(data, config)
    %PREPARE_DATA_NLS Prepara dados - REPLICAÇÃO EXATA DO PYTHON
    %
    % Esta função replica EXATAMENTE a lógica do notebook Python:
    % 2_Translog_Estimation_fixedeffects.ipynb
    %
    % Inputs:
    %   data - Tabela com dados brutos
    %   config - (opcional) struct vazio (para compatibilidade)
    
    if nargin < 2
        config = struct();
    end
    
    stats.n_total = height(data);
    data_clean = data;
    
    fprintf('Preparando dados para estimação...\n');
    
    % =====================================================================
    % CONVERSÃO PARA NUMÉRICO (formato brasileiro)
    % =====================================================================
    
    input_vars = {'variable_input', 'imobilizado', 'receita'};
    
    for i = 1:length(input_vars)
        var = input_vars{i};
        
        % Converter células brasileiras para numérico
        if iscell(data_clean.(var))
            data_clean.(var) = cellfun(@str2double_br, data_clean.(var));
        end
    end
    
    % Python usa 'capital', MATLAB tem 'imobilizado'
    data_clean.capital = data_clean.imobilizado;
    
    % =====================================================================
    % TRATAR VALORES NÃO-POSITIVOS (EXATAMENTE COMO PYTHON)
    % =====================================================================
    
    % Python: pd.to_numeric(..., errors='coerce') + mask = df[var] > 0
    % Depois: df.loc[~mask, var] = np.nan
    
    vars_to_check = {'variable_input', 'capital', 'receita'};
    
    for i = 1:length(vars_to_check)
        var = vars_to_check{i};
        
        % Criar máscara: valores > 0
        mask = data_clean.(var) > 0;
        
        % Contar inválidos
        invalid_count = sum(~mask);
        
        if invalid_count > 0
            fprintf('  Removidas %d observações com valores não-positivos em %s\n', ...
                    invalid_count, var);
            
            % Marcar como NaN (igual Python)
            data_clean.(var)(~mask) = NaN;
        end
    end
    
    % =====================================================================
    % CALCULAR SHARES E LOGS (IGUAL PYTHON)
    % =====================================================================
    
    % Share do insumo variável
    data_clean.share_variable_input = data_clean.variable_input ./ data_clean.receita;
    
    % Calcular logaritmos
    data_clean.log_variable_input = log(data_clean.variable_input);
    data_clean.log_capital = log(data_clean.capital);
    data_clean.log_receita = log(data_clean.receita);
    
    % Termos translog (quadráticos e interações)
    data_clean.log_variable_input_sq = data_clean.log_variable_input .^ 2;
    data_clean.log_capital_sq = data_clean.log_capital .^ 2;
    data_clean.log_v_k_interaction = data_clean.log_variable_input .* data_clean.log_capital;
    
    % =====================================================================
    % REMOVER Inf e NaN (IGUAL PYTHON)
    % =====================================================================
    
    % Python: df.replace([np.inf, -np.inf], np.nan)
    vars_to_replace_inf = {'log_variable_input', 'log_capital', 'log_receita', ...
                           'share_variable_input', 'log_variable_input_sq', ...
                           'log_capital_sq', 'log_v_k_interaction'};
    
    for i = 1:length(vars_to_replace_inf)
        var = vars_to_replace_inf{i};
        if ismember(var, data_clean.Properties.VariableNames)
            data_clean.(var)(isinf(data_clean.(var))) = NaN;
        end
    end
    
    % =====================================================================
    % DROPNA (IGUAL PYTHON: dropna(subset=required_vars))
    % =====================================================================
    
    % Python: required_vars = [f'log_{var}' for var in input_vars] + ['share_variable_input']
    required_vars = {'log_variable_input', 'log_capital', 'log_receita', ...
                     'share_variable_input'};
    
    % Criar máscara de linhas válidas
    valid_rows = true(height(data_clean), 1);
    
    for i = 1:length(required_vars)
        var = required_vars{i};
        valid_rows = valid_rows & ~isnan(data_clean.(var));
    end
    
    % Python: df_prep = df_prep.dropna(subset=required_vars)
    n_before = height(data_clean);
    data_clean = data_clean(valid_rows, :);
    n_after = height(data_clean);
    
    fprintf('Observações válidas: %d/%d (%.1f%%)\n', ...
            n_after, n_before, 100*n_after/n_before);
    
    % =====================================================================
    % ESTATÍSTICAS
    % =====================================================================
    
    stats.n_valid = n_after;
    stats.valid_pct = 100 * n_after / stats.n_total;
    stats.n_removed = stats.n_total - n_after;
    stats.n_firms = length(unique(data_clean.empresa));
    stats.n_sectors = length(unique(data_clean.setor_ipa_7d));
end

function num = str2double_br(x)
    %STR2DOUBLE_BR Converte string brasileira para double
    if isnumeric(x), num = x; return; end
    if isempty(x), num = NaN; return; end
    if iscell(x), x = x{1}; end
    if ~ischar(x), num = NaN; return; end
    x = strtrim(x);
    x = strrep(x, '.', '');   % Remove separador de milhar
    x = strrep(x, ',', '.');  % Vírgula → ponto decimal
    num = str2double(x);
end