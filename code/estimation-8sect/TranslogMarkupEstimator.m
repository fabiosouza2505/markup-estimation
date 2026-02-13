classdef TranslogMarkupEstimator < handle
    %TRANSLOGMARKUPESTIMATOR Classe para estimação de markups via Translog
    %
    % Replica a estrutura da classe Python TranslogMarkupEstimator,
    % implementando a metodologia de De Loecker & Warzynski (2012)
    % para estimação de markups usando função de produção Translog.
    %
    % SINTAXE:
    %   estimator = TranslogMarkupEstimator()
    %   estimator = TranslogMarkupEstimator('ParameterName', ParameterValue, ...)
    %
    % PARÂMETROS (Name-Value pairs):
    %   'polynomial_degree'      - Grau do polinômio (padrão: 3)
    %   'use_fixed_effects'      - Usar efeitos fixos (padrão: true)
    %   'firm_effects'           - Efeitos fixos de firma (padrão: true)
    %   'year_effects'           - Efeitos fixos de ano (padrão: true)
    %   'industry_year_effects'  - Efeitos indústria-ano (padrão: true)
    %   'method'                 - Método: '2sls' ou 'nls' (padrão: '2sls')
    %   'max_markup'             - Markup máximo válido (padrão: 10)
    %   'verbose'                - Exibir mensagens (padrão: true)
    %
    % EXEMPLO:
    %   % Criar estimador
    %   estimator = TranslogMarkupEstimator('method', '2sls', 'verbose', true);
    %   
    %   % Carregar dados
    %   estimator.load_data('data/processed/panel_data.csv');
    %   
    %   % Preparar dados
    %   estimator.prepare_data();
    %   
    %   % Estimar
    %   estimator.estimate();
    %   
    %   % Salvar resultados
    %   estimator.save_results('results/');
    %
    % MÉTODOS PRINCIPAIS:
    %   load_data        - Carrega dados de arquivo
    %   prepare_data     - Prepara dados para estimação
    %   estimate         - Estima modelo Translog
    %   calculate_markups - Calcula markups a partir dos parâmetros
    %   save_results     - Salva resultados em arquivos
    %
    % REFERÊNCIA:
    %   De Loecker, J., & Warzynski, F. (2012). Markups and firm-level 
    %   export status. American Economic Review, 102(6), 2437-2471.
    %
    % Autor: Sistema de Estimação de Markups
    % Data: Dezembro 2024
    
    % =========================================================================
    % PROPRIEDADES (equivalente a atributos em Python)
    % =========================================================================
    
    properties (Access = public)
        % Configurações do modelo
        polynomial_degree       % Grau do polinômio Translog
        use_fixed_effects       % Usar efeitos fixos
        firm_effects            % Efeitos fixos de firma
        year_effects            % Efeitos fixos de ano
        industry_year_effects   % Efeitos indústria-ano
        method                  % Método de estimação ('2sls' ou 'nls')
        max_markup              % Markup máximo válido
        verbose                 % Exibir mensagens
        
        % Dados
        data_raw                % Dados brutos (tabela original)
        data_prep               % Dados preparados
        
        % Resultados
        params                  % Parâmetros estimados
        diagnostics             % Diagnósticos da estimação
        markups                 % Markups calculados
        elasticities            % Elasticidades
        markup_stats            % Estatísticas dos markups
        
        % Estatísticas
        prep_stats              % Estatísticas da preparação
    end
    
    % =========================================================================
    % MÉTODOS
    % =========================================================================
    
    methods (Access = public)
        
        % ─────────────────────────────────────────────────────────────────
        % CONSTRUTOR
        % ─────────────────────────────────────────────────────────────────
        function obj = TranslogMarkupEstimator(varargin)
            %TRANSLOGMARKUPESTIMATOR Construtor da classe
            %
            % SINTAXE:
            %   estimator = TranslogMarkupEstimator()
            %   estimator = TranslogMarkupEstimator('param', value, ...)
            
            % Parser de argumentos
            p = inputParser;
            
            % Adicionar parâmetros opcionais com valores default
            addParameter(p, 'polynomial_degree', 3, @isnumeric);
            addParameter(p, 'use_fixed_effects', true, @islogical);
            addParameter(p, 'firm_effects', true, @islogical);
            addParameter(p, 'year_effects', true, @islogical);
            addParameter(p, 'industry_year_effects', true, @islogical);
            addParameter(p, 'method', '2sls', @ischar);
            addParameter(p, 'max_markup', 10, @isnumeric);
            addParameter(p, 'verbose', true, @islogical);
            
            % Parse inputs
            parse(p, varargin{:});
            
            % Atribuir propriedades (equivalente a self.attr = value)
            obj.polynomial_degree = p.Results.polynomial_degree;
            obj.use_fixed_effects = p.Results.use_fixed_effects;
            obj.firm_effects = p.Results.firm_effects;
            obj.year_effects = p.Results.year_effects;
            obj.industry_year_effects = p.Results.industry_year_effects;
            obj.method = p.Results.method;
            obj.max_markup = p.Results.max_markup;
            obj.verbose = p.Results.verbose;
            
            % Inicializar propriedades vazias
            obj.data_raw = [];
            obj.data_prep = [];
            obj.params = struct();
            obj.diagnostics = struct();
            obj.markups = [];
            obj.elasticities = struct();
            obj.markup_stats = struct();
            obj.prep_stats = struct();
            
            % Mensagem inicial
            if obj.verbose
                fprintf('═══════════════════════════════════════\n');
                fprintf('TRANSLOG MARKUP ESTIMATOR\n');
                fprintf('═══════════════════════════════════════\n');
                fprintf('Configurações:\n');
                fprintf('  Método: %s\n', upper(obj.method));
                fprintf('  Efeitos fixos: %s\n', ...
                        obj.ternary(obj.use_fixed_effects, 'SIM', 'NÃO'));
                fprintf('  Grau polinomial: %d\n', obj.polynomial_degree);
                fprintf('═══════════════════════════════════════\n\n');
            end
        end
        
               
        % ─────────────────────────────────────────────────────────────────
        % LOAD_DATA: Carregar dados de arquivo
        % ─────────────────────────────────────────────────────────────────
        function load_data(obj, filepath)
            %LOAD_DATA Carrega dados de arquivo CSV ou Excel
            %
            % SINTAXE:
            %   estimator.load_data(filepath)
            %
            % INPUT:
            %   filepath - Caminho para arquivo CSV ou Excel
            
            if obj.verbose
                fprintf('─────────────────────────────────────────\n');
                fprintf('CARREGANDO DADOS\n');
                fprintf('─────────────────────────────────────────\n\n');
                fprintf('Arquivo: %s\n', filepath);
            end
            
            % Verificar se arquivo existe
            if ~exist(filepath, 'file')
                error('Arquivo não encontrado: %s', filepath);
            end
            
                % Detectar tipo e carregar
                [~, ~, ext] = fileparts(filepath);
                
                try
                    if strcmp(ext, '.csv')
                        opts = detectImportOptions(filepath, 'Delimiter', ';');
                        opts.VariableNamingRule = 'preserve';  % ← PRESERVAR NOMES ORIGINAIS
                        
                        % FORÇAR leitura de todas as colunas (não truncar)
                        opts.DataLines = [2 Inf];  % Ler da linha 2 até o fim
                        
                        obj.data_raw = readtable(filepath, opts);
                    elseif strcmp(ext, '.xlsx') || strcmp(ext, '.xls')
                        obj.data_raw = readtable(filepath, 'VariableNamingRule', 'preserve');
                    else
                        error('Formato não suportado: %s', ext);
                    end
                    
                    if obj.verbose
                        fprintf('✓ Dados carregados: %d observações × %d variáveis\n\n', ...
                                height(obj.data_raw), width(obj.data_raw));
                    end
                    
                catch ME
                error('Erro ao carregar dados: %s', ME.message);
                end
        end
        
        % ─────────────────────────────────────────────────────────────────
        % PREPARE_DATA: Preparar dados para estimação
        % ─────────────────────────────────────────────────────────────────
        function prepare_data(obj)
            %PREPARE_DATA Prepara dados para estimação Translog
            %
            % Aplica todas as transformações necessárias:
            %   1. Converter para numérico
            %   2. Remover valores inválidos
            %   3. Calcular logaritmos
            %   4. Criar termos Translog
            %   5. Calcular shares
            
            if isempty(obj.data_raw)
                error('Dados não carregados! Execute load_data() primeiro.');
            end
            
            if obj.verbose
                fprintf('─────────────────────────────────────────\n');
                fprintf('PREPARANDO DADOS\n');
                fprintf('─────────────────────────────────────────\n\n');
            end
            
            % Configurar opções
            config = struct();
            config.verbose = obj.verbose;
            config.max_markup = obj.max_markup;
            
            % Chamar função de preparação
            [obj.data_prep, obj.prep_stats] = ...
                prepare_data(obj.data_raw, config);
            
            if obj.verbose
                fprintf('✓ Preparação concluída\n');
                fprintf('  Observações válidas: %d/%d (%.1f%%)\n\n', ...
                        obj.prep_stats.n_valid, ...
                        obj.prep_stats.n_original, ...
                        obj.prep_stats.valid_pct);
            end
        end
        
        % ─────────────────────────────────────────────────────────────────
        % ESTIMATE: Estimar modelo
        % ─────────────────────────────────────────────────────────────────
        function estimate(obj, sector_data)
            %ESTIMATE Estima função de produção Translog
            %
            % SINTAXE:
            %   estimator.estimate()           % Usa todos os dados
            %   estimator.estimate(sector_data) % Usa dados específicos
            
            if isempty(obj.data_prep) && nargin < 2
                error('Dados não preparados! Execute prepare_data() primeiro.');
            end
            
            % Usar dados fornecidos ou dados da classe
            if nargin < 2
                data_to_use = obj.data_prep;
            else
                data_to_use = sector_data;
            end
            
            if obj.verbose
                fprintf('─────────────────────────────────────────\n');
                fprintf('ESTIMANDO MODELO\n');
                fprintf('─────────────────────────────────────────\n\n');
                fprintf('Método: %s\n', upper(obj.method));
                fprintf('Observações: %d\n\n', height(data_to_use));
            end
            
            % Configurar opções
            config = struct();
            config.verbose = obj.verbose;
            
            % Escolher método
            if strcmpi(obj.method, '2sls')
                % Validar dados antes de estimar
                required_vars = {'log_receita', 'log_variable_input', 'log_capital', 'empresa'};
                missing = setdiff(required_vars, data_to_use.Properties.VariableNames);
                if ~isempty(missing)
                    error('Variáveis ausentes nos dados: %s', strjoin(missing, ', '));
                end
                % Estimar via 2SLS
                [obj.params, obj.diagnostics] = ...
                    estimate_translog_2sls(data_to_use, config);
                
            elseif strcmpi(obj.method, 'nls')
                % Estimar via NLS (fminsearch)
                [obj.params, obj.diagnostics] = ...
                    estimate_translog_nls(data_to_use, config);
                
            else
                error('Método inválido: %s. Use ''2sls'' ou ''nls''.', obj.method);
            end
            
            if obj.verbose
                fprintf('✓ Estimação concluída\n');
                fprintf('  R² = %.4f\n', obj.diagnostics.rsquared);
                fprintf('  RMSE = %.4f\n\n', obj.diagnostics.rmse);
            end
        end
        
        % ─────────────────────────────────────────────────────────────────
        % CALCULATE_MARKUPS: Calcular markups
        % ─────────────────────────────────────────────────────────────────
        function calculate_markups(obj, sector_data)
            %CALCULATE_MARKUPS Calcula markups a partir dos parâmetros
            %
            % VERSÃO ATUALIZADA: Agora passa diagnostics para correção ω
            %
            % SINTAXE:
            %   estimator.calculate_markups()
            %   estimator.calculate_markups(sector_data)
            
            if isempty(obj.params)
                error('Modelo não estimado! Execute estimate() primeiro.');
            end
            
            % Usar dados fornecidos ou dados da classe
            if nargin < 2
                data_to_use = obj.data_prep;
            else
                data_to_use = sector_data;
            end
            
            if obj.verbose
                fprintf('─────────────────────────────────────────\n');
                fprintf('CALCULANDO MARKUPS\n');
                fprintf('─────────────────────────────────────────\n\n');
            end
            
            % Configurar opções
            config = struct();
            config.verbose = obj.verbose;
            config.max_markup = obj.max_markup;
            config.apply_productivity_correction = true;  % ← NOVO: Ativar correção ω
            config.show_comparison = false;  % Não mostrar comparação por padrão
            
            % ★★★ CORREÇÃO CRÍTICA: Passar diagnostics para correção ω ★★★
            % Calcular markups COM correção de produtividade
            [obj.markups, obj.elasticities, obj.markup_stats] = ...
                calculate_markups_from_params_weighted(data_to_use, obj.params, obj.diagnostics, config);
            
            if obj.verbose
                fprintf('✓ Markups calculados\n');
                fprintf('  Markup médio: %.3f\n', obj.markup_stats.mean);
                fprintf('  Intervalo: [%.3f - %.3f]\n\n', ...
                        obj.markup_stats.min, obj.markup_stats.max);
            end
        end
        
        % ─────────────────────────────────────────────────────────────────
        % SAVE_RESULTS: Salvar resultados
        % ─────────────────────────────────────────────────────────────────
        function save_results(obj, output_dir, prefix)
            %SAVE_RESULTS Salva resultados em arquivos
            %
            % SINTAXE:
            %   estimator.save_results(output_dir)
            %   estimator.save_results(output_dir, prefix)
            %
            % INPUTS:
            %   output_dir - Diretório de saída
            %   prefix     - (Opcional) Prefixo para nomes de arquivos
            
            if nargin < 3
                prefix = sprintf('resultados_%s', obj.method);
            end
            
            if obj.verbose
                fprintf('─────────────────────────────────────────\n');
                fprintf('SALVANDO RESULTADOS\n');
                fprintf('─────────────────────────────────────────\n\n');
            end
            
            % Criar diretório se não existir
            if ~exist(output_dir, 'dir')
                mkdir(output_dir);
            end
            
            % 1. Salvar parâmetros
            if ~isempty(obj.params)
                params_table = obj.params_to_table();
                params_file = fullfile(output_dir, sprintf('%s_parametros.csv', prefix));
                writetable(params_table, params_file);
                
                if obj.verbose
                    fprintf('✓ Parâmetros: %s\n', params_file);
                end
            end
            
            % 2. Salvar estatísticas de markups
            if ~isempty(obj.markup_stats)
                stats_table = obj.markup_stats_to_table();
                stats_file = fullfile(output_dir, sprintf('%s_markups_stats.csv', prefix));
                writetable(stats_table, stats_file);
                
                if obj.verbose
                    fprintf('✓ Estatísticas: %s\n', stats_file);
                end
            end
            
            % 3. Salvar workspace completo
            workspace_file = fullfile(output_dir, sprintf('%s_workspace.mat', prefix));
            save(workspace_file, 'obj');
            
            if obj.verbose
                fprintf('✓ Workspace: %s\n', workspace_file);
            end
            
            % 4. Salvar relatório em texto
            report_file = fullfile(output_dir, sprintf('%s_relatorio.txt', prefix));
            obj.write_report(report_file);
            
            if obj.verbose
                fprintf('✓ Relatório: %s\n\n', report_file);
            end
        end
        
        % ─────────────────────────────────────────────────────────────────
        % DISPLAY: Exibir resumo do objeto
        % ─────────────────────────────────────────────────────────────────
        function display(obj)
            %DISPLAY Exibe informações sobre o estimador
            
            fprintf('\n');
            fprintf('═══════════════════════════════════════\n');
            fprintf('TranslogMarkupEstimator\n');
            fprintf('═══════════════════════════════════════\n');
            fprintf('Método: %s\n', upper(obj.method));
            fprintf('Efeitos fixos: %s\n', ...
                    obj.ternary(obj.use_fixed_effects, 'SIM', 'NÃO'));
            fprintf('\n');
            
            fprintf('Dados:\n');
            if ~isempty(obj.data_raw)
                fprintf('  Raw: %d obs × %d vars\n', ...
                        height(obj.data_raw), width(obj.data_raw));
            else
                fprintf('  Raw: (não carregados)\n');
            end
            
            if ~isempty(obj.data_prep)
                fprintf('  Prep: %d obs\n', height(obj.data_prep));
            else
                fprintf('  Prep: (não preparados)\n');
            end
            fprintf('\n');
            
            fprintf('Resultados:\n');
            if ~isempty(obj.params)
                fprintf('  Modelo estimado: ✓\n');
                fprintf('  R² = %.4f\n', obj.diagnostics.rsquared);
            else
                fprintf('  Modelo estimado: ✗\n');
            end
            
            if ~isempty(obj.markups)
                fprintf('  Markups calculados: ✓\n');
                fprintf('  Markup médio = %.3f\n', obj.markup_stats.mean);
            else
                fprintf('  Markups calculados: ✗\n');
            end
            
            fprintf('═══════════════════════════════════════\n\n');
        end
        
    end  % Fim de methods (public)
    
    % =========================================================================
    % MÉTODOS PRIVADOS (equivalente a métodos com _ em Python)
    % =========================================================================
    
    methods (Access = private)
        
        % Converter parâmetros para tabela
        function tbl = params_to_table(obj)
            tbl = table();
            tbl.parametro = {'beta0'; 'beta_k'; 'beta_kk'; 'beta_omega'; ...
                             'beta_v'; 'beta_vv'; 'beta_vk'};
            tbl.valor = [obj.params.beta0; obj.params.beta_k; ...
                         obj.params.beta_kk; obj.params.beta_omega; ...
                         obj.params.beta_v; obj.params.beta_vv; ...
                         obj.params.beta_vk];
        end
        
        % Converter estatísticas de markups para tabela
        function tbl = markup_stats_to_table(obj)
            tbl = table();
            tbl.estatistica = {'mean'; 'median'; 'std'; 'min'; 'max'; ...
                               'p25'; 'p75'; 'pct_above_1'};
            tbl.valor = [obj.markup_stats.mean; obj.markup_stats.median; ...
                         obj.markup_stats.std; obj.markup_stats.min; ...
                         obj.markup_stats.max; obj.markup_stats.p25; ...
                         obj.markup_stats.p75; obj.markup_stats.pct_above_1];
        end
        
        % Escrever relatório em texto
        function write_report(obj, filepath)
            fid = fopen(filepath, 'w');
            
            fprintf(fid, '═══════════════════════════════════════\n');
            fprintf(fid, 'RELATÓRIO DE ESTIMAÇÃO DE MARKUPS\n');
            fprintf(fid, '═══════════════════════════════════════\n\n');
            
            fprintf(fid, 'MÉTODO: %s\n\n', upper(obj.method));
            
            if ~isempty(obj.params)
                fprintf(fid, 'PARÂMETROS (Exógenas):\n');
                fprintf(fid, '  β₀  = %8.4f  (Constante)\n', obj.params.beta0);
                fprintf(fid, '  β_k = %8.4f  (Capital)\n', obj.params.beta_k);
                fprintf(fid, '  β_kk = %8.4f  (Capital²)\n', obj.params.beta_kk);
                fprintf(fid, '  β_ω  = %8.4f  (Produtividade)\n\n', obj.params.beta_omega);

                fprintf(fid, 'PARÂMETROS (Endógenas — instrumentalizadas):\n');
                fprintf(fid, '  β_v = %8.4f  (Insumo variável)\n', obj.params.beta_v);
                fprintf(fid, '  β_vv = %8.4f  (Insumo variável²)\n', obj.params.beta_vv);
                fprintf(fid, '  β_vk = %8.4f  (Interação V×K)\n\n', obj.params.beta_vk);

                fprintf(fid, 'QUALIDADE DO AJUSTE:\n');
                fprintf(fid, '  R² (forma reduzida) = %.4f\n', obj.diagnostics.reduced_form_r2);
                fprintf(fid, '  R² (2SLS) = %.4f\n', obj.diagnostics.rsquared);
                fprintf(fid, '  RMSE = %.4f\n\n', obj.diagnostics.rmse);
            end
            
            if ~isempty(obj.markup_stats)
                fprintf(fid, 'MARKUPS:\n');
                fprintf(fid, '  Média = %.3f\n', obj.markup_stats.mean);
                fprintf(fid, '  Mediana = %.3f\n', obj.markup_stats.median);
                fprintf(fid, '  Desvio = %.3f\n', obj.markup_stats.std);
                fprintf(fid, '  Min-Max = [%.3f - %.3f]\n', ...
                        obj.markup_stats.min, obj.markup_stats.max);
            end
            
            fclose(fid);
        end
        
        % Função auxiliar: operador ternário
        function result = ternary(~, condition, true_val, false_val)
            if condition
                result = true_val;
            else
                result = false_val;
            end
        end
        
    end  % Fim de methods (private)
    
end  % Fim da classe
