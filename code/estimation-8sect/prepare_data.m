function [data_clean, stats] = prepare_data(data, config)
    %PREPARE_DATA_NLS Prepara dados para estimação Translog
    %
    % Replica a função prepare_data() do código Python, preparando os dados
    % brutos para estimação de markups com função Translog.
    %
    % SINTAXE:
    %   [data_clean, stats] = prepare_data(data)
    %   [data_clean, stats] = prepare_data(data, config)
    %
    % INPUTS:
    %   data   - Tabela MATLAB com dados brutos contendo:
    %            • variable_input (custos variáveis)
    %            • imobilizado (capital fixo)
    %            • receita (receita operacional líquida)
    %            • empresa, ano, trimestre (identificadores)
    %            • setor_ipa_7d (código do setor)
    %
    %   config - (Opcional) Struct com configurações:
    %            • verbose (bool): Exibir mensagens (default: true)
    %            • max_markup (double): Markup máximo válido (default: 10)
    %
    % OUTPUTS:
    %   data_clean - Tabela com dados preparados contendo:
    %                • log_receita, log_variable_input, log_capital
    %                • share_variable_input (α_v = V/R)
    %                • Termos quadráticos e interações Translog
    %                • Identificadores originais
    %
    %   stats      - Struct com estatísticas da preparação:
    %                • n_original, n_valid, valid_pct
    %                • n_removed_by_reason (detalhamento de remoções)
    %
    % TRANSFORMAÇÕES REALIZADAS:
    %   1. Converter células para numérico (formato brasileiro)
    %   2. Remover valores não-positivos (≤ 0)
    %   3. Calcular shares dos insumos
    %   4. Calcular logaritmos
    %   5. Criar termos quadráticos e interações (Translog)
    %   6. Remover NaN e Inf
    %   7. Filtrar outliers (shares < 0.001 ou > 0.999)
    %
    % EXEMPLO:
    %   data = readtable('data/processed/panel_data.csv');
    %   [data_clean, stats] = prepare_data(data);
    %   fprintf('Válidos: %d/%d (%.1f%%)\n', ...
    %           stats.n_valid, stats.n_original, stats.valid_pct);
    %
    % REFERÊNCIA:
    %   Baseado em TranslogMarkupEstimator.prepare_data() do código Python
    %
    % Autor: Sistema de Estimação de Markups
    % Data: Dezembro 2024
    
    % =========================================================================
    % CONFIGURAÇÕES INICIAIS
    % =========================================================================
    
    % Parâmetros default
    if nargin < 2
        config = struct();
    end
    
    if ~isfield(config, 'verbose')
        config.verbose = true;
    end
    
    if ~isfield(config, 'max_markup')
        config.max_markup = 10;
    end
    
    % Iniciar mensagem
    if config.verbose
        fprintf('========================================\n');
        fprintf('PREPARAÇÃO DE DADOS PARA TRANSLOG\n');
        fprintf('========================================\n\n');
    end
    
    % Contador de observações
    n_original = height(data);
    
    if config.verbose
        fprintf('1. Dados originais: %d observações\n\n', n_original);
    end
    
    % Inicializar estrutura de estatísticas
    stats = struct();
    stats.n_original = n_original;
    stats.n_removed_by_reason = struct();
    
    % =========================================================================
    % PASSO 1: CONVERTER CÉLULAS PARA NUMÉRICO (FORMATO BRASILEIRO)
    % =========================================================================
    
    if config.verbose
        fprintf('2. Convertendo dados para numérico...\n');
    end
    
    % Variáveis essenciais
    input_vars = {'variable_input', 'imobilizado', 'receita'};
    
    % FLEXIBILIDADE: Aceitar 'capital' se 'imobilizado' não existir
    if ~ismember('imobilizado', data.Properties.VariableNames) && ...
       ismember('capital', data.Properties.VariableNames)
        if config.verbose
            fprintf('   ℹ Usando "capital" ao invés de "imobilizado"\n');
        end
        data.imobilizado = data.capital;
    end
    
    % Para cada variável, converter de string/cell para double
    for i = 1:length(input_vars)
        var_name = input_vars{i};
        
        % Verificar se variável existe
        if ~ismember(var_name, data.Properties.VariableNames)
            error('Variável %s não encontrada nos dados!', var_name);
        end
        
        % Obter coluna
        col = data.(var_name);
        
        % Se for cell array (string), converter
        if iscell(col)
            if config.verbose
                fprintf('   Convertendo %s de cell para numeric...\n', var_name);
            end
            
            % Chama a função auxiliar str2double_br para converter formato brasileiro
            col_numeric = str2double_br(col);
            
            % Substituir na tabela
            data.(var_name) = col_numeric;
        end
    end
    
    if config.verbose
        fprintf('   ✓ Conversão concluída\n\n');
    end
    
    % =========================================================================
    % PASSO 2: MARCAR VALORES NÃO-POSITIVOS COMO NaN
    % =========================================================================
    
    if config.verbose
        fprintf('3. Identificando valores inválidos...\n');
    end
    
    % Para cada variável, marcar valores ≤ 0 como NaN
    for i = 1:length(input_vars)
        var_name = input_vars{i};
        
        % Obter coluna
        col = data.(var_name);
        
        % Máscara de valores válidos (> 0)
        valid_mask = col > 0;
        
        % Contar inválidos
        n_invalid = sum(~valid_mask);
        
        if n_invalid > 0
            if config.verbose
                fprintf('   %s: %d valores não-positivos marcados como NaN\n', ...
                        var_name, n_invalid);
            end
            
            % Marcar como NaN
            col(~valid_mask) = NaN;
            
            % Atualizar tabela
            data.(var_name) = col;
            
            % Registrar estatística
            stats.n_removed_by_reason.(sprintf('nonpositive_%s', var_name)) = n_invalid;
        end
    end
    
    if config.verbose
        fprintf('   ✓ Validação concluída\n\n');
    end
    
    % =========================================================================
    % PASSO 3: CALCULAR SHARES DOS INSUMOS
    % =========================================================================
    
    if config.verbose
        fprintf('4. Calculando shares dos insumos...\n');
    end
    
    % Share do insumo variável: α_v = V / R
    data.share_variable_input = data.variable_input ./ data.receita;
    
    % Share do capital: α_k = K / R (opcional, mas útil)
    data.share_capital = data.imobilizado ./ data.receita;
    
    if config.verbose
        fprintf('   ✓ Shares calculados\n\n');
    end
    
    % =========================================================================
    % PASSO 4: CALCULAR LOGARITMOS
    % =========================================================================
    
    if config.verbose
        fprintf('5. Calculando logaritmos...\n');
    end
    
    % Criar novas colunas com logaritmos
    data.log_receita = log(data.receita);
    data.log_variable_input = log(data.variable_input);
    data.log_capital = log(data.imobilizado);  % Renomear para consistência
    
    if config.verbose
        fprintf('   ✓ Logaritmos calculados\n\n');
    end
    
    % =========================================================================
    % PASSO 5: CRIAR TERMOS TRANSLOG (QUADRÁTICOS E INTERAÇÕES)
    % =========================================================================
    
    if config.verbose
        fprintf('6. Criando termos da função Translog...\n');
    end
    
    % Termos quadráticos
    data.log_variable_input_sq = data.log_variable_input .^ 2;
    data.log_capital_sq = data.log_capital .^ 2;
    
    % Termo de interação
    data.log_v_k_interaction = data.log_variable_input .* data.log_capital;
    
    if config.verbose
        fprintf('   Termos criados:\n');
        fprintf('     • log(V)²\n');
        fprintf('     • log(K)²\n');
        fprintf('     • log(V) × log(K)\n');
        fprintf('   ✓ Termos Translog criados\n\n');
    end
    
    % =========================================================================
    % PASSO 6: SUBSTITUIR INFINITOS POR NaN
    % =========================================================================
    
    if config.verbose
        fprintf('7. Tratando valores infinitos...\n');
    end
    
    % Variáveis numéricas a verificar
    numeric_vars = data.Properties.VariableNames;
    
    n_inf_total = 0;
    
    for i = 1:length(numeric_vars)
        var_name = numeric_vars{i};
        
        % Verificar se é numérica
        if isnumeric(data.(var_name))
            col = data.(var_name);
            
            % Máscara de infinitos
            inf_mask = isinf(col);
            n_inf = sum(inf_mask);
            
            if n_inf > 0
                % Substituir Inf por NaN
                col(inf_mask) = NaN;
                data.(var_name) = col;
                
                n_inf_total = n_inf_total + n_inf;
            end
        end
    end
    
    if config.verbose
        if n_inf_total > 0
            fprintf('   %d valores infinitos substituídos por NaN\n', n_inf_total);
        end
        fprintf('   ✓ Infinitos tratados\n\n');
    end
    
    % =========================================================================
    % PASSO 7: REMOVER OBSERVAÇÕES COM NaN NAS VARIÁVEIS ESSENCIAIS
    % =========================================================================
    
    if config.verbose
        fprintf('8. Removendo observações com valores faltantes...\n');
    end
    
    % Variáveis essenciais que não podem ter NaN
    required_vars = {
        'log_receita', 
        'log_variable_input', 
        'log_capital',
        'share_variable_input'
    };
    
    % Criar máscara de linhas válidas (sem NaN em nenhuma variável essencial)
    valid_mask = true(height(data), 1);
    
    for i = 1:length(required_vars)
        var_name = required_vars{i};
        valid_mask = valid_mask & ~isnan(data.(var_name));
    end
    
    % Contar removidos
    n_removed_nan = sum(~valid_mask);
    
    if config.verbose && n_removed_nan > 0
        fprintf('   %d observações removidas (NaN em variáveis essenciais)\n', ...
                n_removed_nan);
    end
    
    % Filtrar dados
    data_clean = data(valid_mask, :);
    
    % Registrar estatística
    stats.n_removed_by_reason.missing_values = n_removed_nan;
    
    if config.verbose
        fprintf('   ✓ Observações válidas: %d\n\n', height(data_clean));
    end
    
    % =========================================================================
    % PASSO 8: FILTRAR OUTLIERS DE SHARES (OPCIONAL)
    % =========================================================================
    
    % NOTA: No código original Python, não há filtro explícito de shares extremos
    % Mas é uma boa prática remover shares muito próximos de 0 ou 1
    % Comente este bloco se quiser replicar exatamente o Python
    
    % if config.verbose
    %     fprintf('9. Filtrando outliers de shares...\n');
    % end
    % 
    % % Filtro: 0.001 < share < 0.999
    % share_valid = (data_clean.share_variable_input > 0.001) & ...
    %               (data_clean.share_variable_input < 0.999);
    % 
    % n_removed_shares = sum(~share_valid);
    % 
    % if n_removed_shares > 0 && config.verbose
    %     fprintf('   %d observações removidas (shares extremos)\n', n_removed_shares);
    % end
    % 
    % data_clean = data_clean(share_valid, :);
    % stats.n_removed_by_reason.extreme_shares = n_removed_shares;
    % 
    % if config.verbose
    %     fprintf('   ✓ Filtro de shares aplicado\n\n');
    % end
    
    % =========================================================================
    % PASSO 9: ESTATÍSTICAS FINAIS
    % =========================================================================
    
    n_valid = height(data_clean);
    valid_pct = (n_valid / n_original) * 100;
    
    stats.n_valid = n_valid;
    stats.valid_pct = valid_pct;
    
    if config.verbose
        fprintf('========================================\n');
        fprintf('RESUMO DA PREPARAÇÃO\n');
        fprintf('========================================\n\n');
        fprintf('Observações originais:    %6d\n', n_original);
        fprintf('Observações válidas:      %6d\n', n_valid);
        fprintf('Taxa de aproveitamento:   %6.1f%%\n', valid_pct);
        fprintf('\n');
        
        % Detalhamento de remoções
        if ~isempty(fieldnames(stats.n_removed_by_reason))
            fprintf('Detalhamento de remoções:\n');
            reasons = fieldnames(stats.n_removed_by_reason);
            for i = 1:length(reasons)
                reason = reasons{i};
                n_removed = stats.n_removed_by_reason.(reason);
                fprintf('  • %-25s: %d\n', strrep(reason, '_', ' '), n_removed);
            end
            fprintf('\n');
        end
        
        fprintf('Variáveis criadas:\n');
        fprintf('  • Logaritmos: log_receita, log_variable_input, log_capital\n');
        fprintf('  • Shares: share_variable_input, share_capital\n');
        fprintf('  • Termos Translog: log_variable_input_sq, log_capital_sq, log_v_k_interaction\n');
        fprintf('\n');
        
        fprintf('✓ PREPARAÇÃO CONCLUÍDA COM SUCESSO!\n');
        fprintf('========================================\n\n');
    end
    
end  % Fim da função prepare_data
