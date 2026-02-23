function main()
    %MAIN Estimação de markups via função de produção Translog
    %
    % Arquitetura funcional com suporte a múltiplos métodos de estimação.
    % Executa 2SLS, NLS e/ou GMM-ACF por setor, armazena resultados
    % separadamente e permite comparação cross-method.
    %
    % FLUXO:
    %   1. Configuração e caminhos
    %   2. Carregar e preparar dados
    %   3. Mapear variáveis para nomes canônicos (log_q, log_v, log_k)
    %   4. Identificar setores
    %   5. Loop: método × setor
    %   6. Salvar resultados (por método)
    %   7. Resumo e comparação
    %
    % FUNÇÕES EXTERNAS:
    %   prepare_data()                              → preparação do painel
    %   estimate_translog()                         → despacha para 2SLS, NLS ou GMM-ACF
    %   estimate_translog_gmm_acf()                 → GMM não-linear ACF (W = I)
    %   compute_phi()                               → Estágio 1 ACF: Φ(β)
    %   compute_innovation()                        → Estágio 2 ACF: ξ(β) via Markov
    %   compute_moments()                           → Condições de momento g(β)
    %   objective_gmm()                             → Critério Q(β) para fminsearch
    %   calculate_markups_from_params_weighted()     → cálculo de markups
    %   save_multiple_sectors_results()              → CSVs resumo
    %   save_estimation_results()                    → CSV firma-período
    %   plot_markup_results()                        → plotagem (futuro)
    %
    % REFERÊNCIAS:
    %   De Loecker, J., & Warzynski, F. (2012). Markups and firm-level
    %   export status. American Economic Review, 102(6), 2437-2471.
    %
    %   Ackerberg, D., Caves, K., & Frazer, G. (2015). Identification
    %   properties of recent production function estimators.
    %   Econometrica, 83(6), 2411-2451.
    %
    % Autor: Fabio de Medeiros Souza
    % Data: Fevereiro 2025
    
    clearvars -except varargin;
    close all;
    clc;
    
    % =====================================================================
    % 1. CONFIGURAÇÃO
    % =====================================================================
    
    % Caminhos
    input_path = 'C:/Users/fabio/OneDrive/Documents/MATLAB/markup-estimation/data/processed/estimation-8sect/final_data.csv';
    output_dir = 'C:/Users/fabio/OneDrive/Documents/MATLAB/markup-estimation/results/estimation-8sect/';
    
    % ── Métodos de estimação ──
    % Opções: '2sls', 'nls', 'gmm_acf', ou qualquer combinação.
    % Para curva de aprendizado do GMM-ACF, use apenas {'gmm_acf'}.
    % Para validação cruzada completa, use {'2sls', 'nls', 'gmm_acf'}.
    config = struct();
    config.methods            = {'2sls', 'nls', 'gmm_acf'};
    config.polynomial_degree  = 3;
    config.max_markup         = 10;
    config.min_obs_sector     = 30;
    config.verbose            = true;

    % ── Configurações específicas do GMM-ACF ──
    config.markov_degree  = 3;      % grau do polinômio de Markov para ω
    config.n_lags         = 5;      % lags temporais nos instrumentos (18 total)
    config.n_starts       = 20;     % pontos iniciais multi-start (passo 1)
    config.n_starts_step2 = 10;     % pontos iniciais multi-start (passo 2)
    config.max_iter       = 5000;   % máximo de iterações do Nelder-Mead por start
    config.tol_fun        = 1e-10;  % tolerância da função objetivo
    config.tol_x          = 1e-10;  % tolerância dos parâmetros
    config.seed_from_ols  = true;   % usar Cobb-Douglas OLS como ponto inicial
    config.two_step       = true;   % GMM em dois passos (Hansen, 1982)

    % ── Configurações de markups ──
    config.apply_productivity_correction = true;
    config.show_comparison = false;
    
    fprintf('═══════════════════════════════════════\n');
    fprintf('ESTIMAÇÃO DE MARKUPS — TRANSLOG\n');
    fprintf('═══════════════════════════════════════\n\n');
    fprintf('  Input:   %s\n', input_path);
    fprintf('  Output:  %s\n', output_dir);
    fprintf('  Métodos: %s\n\n', strjoin(upper(config.methods), ' + '));
    
    % Verificar arquivo de entrada
    if ~exist(input_path, 'file')
        error('Arquivo de entrada não encontrado: %s', input_path);
    end
    
    % Criar diretório de output
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % =====================================================================
    % 2. CARREGAR E PREPARAR DADOS
    % =====================================================================
    
    fprintf('─── CARREGANDO DADOS ───\n\n');
    
    try
        opts = detectImportOptions(input_path, 'Delimiter', ';');
        opts.VariableNamingRule = 'preserve';
        opts.DataLines = [2 Inf];
        data_raw = readtable(input_path, opts);
        
        fprintf('  ✓ %d observações × %d variáveis\n\n', ...
                height(data_raw), width(data_raw));
    catch ME
        error('Erro ao carregar dados: %s', ME.message);
    end
    
    fprintf('─── PREPARANDO DADOS ───\n\n');
    
    try
        [data_prep, prep_stats] = prepare_data(data_raw, config);
        fprintf('  ✓ %d/%d observações válidas (%.1f%%)\n\n', ...
                prep_stats.n_valid, prep_stats.n_original, prep_stats.valid_pct);
    catch ME
        error('Erro na preparação: %s', ME.message);
    end
    
    if prep_stats.n_valid == 0
        error('Nenhuma observação válida após preparação!');
    end
    
    % Validar variáveis necessárias
    required_vars = {'log_receita', 'log_variable_input', 'log_capital', ...
                     'empresa', 'share_variable_input'};
    missing = setdiff(required_vars, data_prep.Properties.VariableNames);
    if ~isempty(missing)
        error('Variáveis ausentes: %s', strjoin(missing, ', '));
    end
    
    % ── Mapeamento para nomes canônicos ──────────────────────────────────
    % O GMM-ACF (compute_phi, compute_innovation, compute_moments) usa os
    % nomes padronizados: log_q, log_v, log_k.
    % O 2SLS e o NLS continuam usando log_receita / log_variable_input /
    % log_capital internamente — o mapeamento abaixo adiciona aliases sem
    % remover as colunas originais, garantindo compatibilidade com todo
    % o pipeline existente.
    data_prep.log_q = data_prep.log_receita;
    data_prep.log_v = data_prep.log_variable_input;
    data_prep.log_k = data_prep.log_capital;
    
    % =====================================================================
    % 3. IDENTIFICAR SETORES
    % =====================================================================
    
    if ~ismember('setor_ipa_7d', data_prep.Properties.VariableNames)
        fprintf('Coluna de setor não encontrada. Estimando pool...\n\n');
        results = run_pool_estimation(data_prep, config);
        assignin('base', 'results', results);
        return;
    end
    
    setores = unique(data_prep.setor_ipa_7d);
    n_setores = length(setores);
    
    fprintf('─── SETORES ───\n\n');
    fprintf('  Encontrados: %d\n', n_setores);
    for i = 1:min(n_setores, 10)
        fprintf('    • %d\n', setores(i));
    end
    if n_setores > 10
        fprintf('    ... e mais %d\n', n_setores - 10);
    end
    fprintf('\n');
    
    % Menu
    fprintf('  [1] Estimar todos os setores\n');
    fprintf('  [2] Estimar um setor específico\n');
    opcao = input('  Escolha [1/2]: ', 's');
    if isempty(opcao), opcao = '1'; end
    fprintf('\n');
    
    % =====================================================================
    % 4. PREPARAR DADOS SETORIAIS
    % =====================================================================
    
    % Construir lista de setores a estimar
    switch opcao
        case '1'
            setores_estimar = setores;
        case '2'
            fprintf('Setores disponíveis:\n');
            for i = 1:n_setores
                fprintf('  [%2d] Setor %d\n', i, setores(i));
            end
            fprintf('\n');
            idx = input(sprintf('  Escolha [1-%d]: ', n_setores));
            if isempty(idx) || idx < 1 || idx > n_setores
                error('Índice inválido!');
            end
            setores_estimar = setores(idx);
            fprintf('\n');
        otherwise
            error('Opção inválida!');
    end
    
    n_estimar = length(setores_estimar);
    
    % Pré-filtrar e ordenar dados por setor
    sector_list = cell(n_estimar, 1);   % {struct com .name, .data}
    
    for i = 1:n_estimar
        s = struct();
        s.codigo = setores_estimar(i);
        
        % Filtrar
        s.data = data_prep(data_prep.setor_ipa_7d == s.codigo, :);
        
        % Ordenar por empresa e tempo
        sort_vars = {'empresa', 'ano'};
        if ismember('trimestre', s.data.Properties.VariableNames)
            sort_vars{end+1} = 'trimestre'; %#ok<AGROW>
        end
        s.data = sortrows(s.data, sort_vars);
        
        % Nome
        if ismember('nome_setor', s.data.Properties.VariableNames)
            s.name = s.data.nome_setor{1};
        else
            s.name = sprintf('Setor %d', s.codigo);
        end
        
        s.n_obs = height(s.data);
        sector_list{i} = s;
    end
    
    % =====================================================================
    % 5. LOOP: MÉTODO × SETOR
    % =====================================================================
    
    n_methods = length(config.methods);
    results = struct();     % results.tsls, results.nls, etc.
    
    for m = 1:n_methods
        method = config.methods{m};
        method_upper = upper(method);
        
        fprintf('═══════════════════════════════════════\n');
        fprintf('  MÉTODO: %s\n', method_upper);
        fprintf('═══════════════════════════════════════\n\n');
        
        % Config específica do método
        config_m = config;
        config_m.method = method;
        
        % Inicializar struct de resultados para este método
        res = struct();
        res.method           = method;
        res.setores          = {};
        res.params           = {};
        res.diagnostics      = {};
        res.markup_stats     = {};
        res.markups_raw      = {};
        res.elasticities_raw = {};
        res.sector_data      = {};
        
        for i = 1:n_estimar
            s = sector_list{i};
            
            % Header
            fprintf('[%2d/%2d] %-40s n=%4d | ', ...
                    i, n_estimar, truncate_str(s.name, 40), s.n_obs);
            
            % Verificar observações mínimas
            if s.n_obs < config.min_obs_sector
                fprintf('SKIP (n < %d)\n', config.min_obs_sector);
                continue;
            end
            
            % Verificar viabilidade dos lags (5 lags por empresa)
            n_empresas = length(unique(s.data.empresa));
            obs_por_empresa = s.n_obs / n_empresas;
            if obs_por_empresa <= 5
                fprintf('SKIP (%.1f obs/empresa)\n', obs_por_empresa);
                continue;
            end
            
            try
                % Estimar (verbose off no loop)
                config_quiet = config_m;
                config_quiet.verbose = false;
                
                % ── Injetar seed do 2SLS para GMM-ACF ──
                % Se estamos rodando gmm_acf E já temos resultados do 2SLS
                % para este setor, usar os betas do 2SLS como ponto inicial
                % adicional. Isso guia o otimizador para a vizinhança correta.
                if strcmpi(method, 'gmm_acf') && isfield(results, 'x2sls')
                    res_2sls = results.x2sls;
                    idx_2sls = find(strcmp(res_2sls.setores, s.name), 1);
                    if ~isempty(idx_2sls)
                        p2 = res_2sls.params{idx_2sls};
                        config_quiet.beta_2sls = [p2.beta_v, p2.beta_k, ...
                            p2.beta_vv, p2.beta_kk, p2.beta_vk];
                    end
                end
                
                [params, diagnostics] = ...
                    estimate_translog(s.data, config_quiet);
                
                % Calcular markups
                [markups, elasticities, markup_stats] = ...
                    calculate_markups_from_params_weighted( ...
                        s.data, params, diagnostics, config_quiet);
                
                % Armazenar
                res.setores{end+1}          = s.name;           
                res.params{end+1}           = params;           %#ok<AGROW>
                res.diagnostics{end+1}      = diagnostics;      %#ok<AGROW>
                res.markup_stats{end+1}     = markup_stats;     %#ok<AGROW>
                res.markups_raw{end+1}      = markups;          %#ok<AGROW>
                res.elasticities_raw{end+1} = elasticities;     %#ok<AGROW>
                res.sector_data{end+1}      = s.data;           %#ok<AGROW>
                
                fprintf('μ=%.3f | R²=%.3f ✓\n', ...
                        markup_stats.mean, diagnostics.rsquared);
                
            catch ME
                fprintf('ERRO: %s\n', ME.message);
            end
        end
        
        fprintf('\n  %s: %d/%d setores estimados\n\n', ...
                method_upper, length(res.setores), n_estimar);
        
        % Guardar resultados deste método
        results.(method_field(method)) = res;
    end
    
    % =====================================================================
    % 6. SALVAR RESULTADOS (POR MÉTODO)
    % =====================================================================
    
    fprintf('─── SALVANDO RESULTADOS ───\n\n');
    
    for m = 1:n_methods
        method = config.methods{m};
        res = results.(method_field(method));
        
        if isempty(res.setores)
            fprintf('  %s: nenhum setor estimado, nada a salvar.\n', upper(method));
            continue;
        end
        
        % Subdiretório por método
        method_dir = fullfile(output_dir, method);
        if ~exist(method_dir, 'dir')
            mkdir(method_dir);
        end
        
        fprintf('  [%s]\n', upper(method));
        
        try
            save_multiple_sectors_results(res, method_dir);
            save_estimation_results(res, method_dir);
        catch ME
            warning('Erro ao salvar %s: %s', method, ME.message);
        end
        
        fprintf('\n');
    end
    
    fprintf('  ✓ Resultados salvos em: %s\n\n', output_dir);
    
    % =====================================================================
    % 7. RESUMO FINAL
    % =====================================================================
    
    fprintf('═══════════════════════════════════════\n');
    fprintf('RESUMO\n');
    fprintf('═══════════════════════════════════════\n\n');
    
    for m = 1:n_methods
        method = config.methods{m};
        res = results.(method_field(method));
        
        if isempty(res.setores)
            continue;
        end
        
        all_means = cellfun(@(x) x.mean, res.markup_stats);
        all_r2 = cellfun(@(x) x.rsquared, res.diagnostics);
        
        fprintf('  %s:\n', upper(method));
        fprintf('    Setores: %d | μ médio: %.3f | R² médio: %.3f\n\n', ...
                length(res.setores), mean(all_means), mean(all_r2));
    end
    
    % =====================================================================
    % 8. COMPARAÇÃO CROSS-METHOD (se dois ou mais métodos rodaram)
    % =====================================================================
    
    methods_with_results = {};
    for m = 1:n_methods
        res_m = results.(method_field(config.methods{m}));
        if ~isempty(res_m.setores)
            methods_with_results{end+1} = config.methods{m}; %#ok<AGROW>
        end
    end
    
    if length(methods_with_results) >= 2
        fprintf('─── COMPARAÇÃO CROSS-METHOD ───\n\n');
        print_cross_method_comparison(results, methods_with_results);
    end
    
    % =====================================================================
    % 9. EXPORTAR PARA WORKSPACE
    % =====================================================================
    
    assignin('base', 'results', results);
    assignin('base', 'config', config);
    fprintf('  ✓ results e config exportados para o workspace\n\n');
    
    % =====================================================================
    % 10. PLOTAGEM (futuro)
    % =====================================================================
    % Descomentar quando implementada:
    % plot_markup_results(results, output_dir, config);
    
end


% =========================================================================
% FUNÇÕES AUXILIARES LOCAIS
% =========================================================================

function results = run_pool_estimation(data_prep, config)
    %RUN_POOL_ESTIMATION Estima sem divisão por setor (pool)
    
    results = struct();
    
    for m = 1:length(config.methods)
        method = config.methods{m};
        config_m = config;
        config_m.method = method;
        
        fprintf('  Estimando pool via %s...\n', upper(method));
        
        [params, diagnostics] = estimate_translog(data_prep, config_m);
        [markups, elasticities, markup_stats] = ...
            calculate_markups_from_params_weighted( ...
                data_prep, params, diagnostics, config_m);
        
        res = struct();
        res.method       = method;
        res.params       = params;
        res.diagnostics  = diagnostics;
        res.markup_stats = markup_stats;
        res.markups      = markups;
        res.elasticities = elasticities;
        
        results.(method_field(method)) = res;
        
        fprintf('  ✓ %s: μ=%.3f | R²=%.3f\n\n', ...
                upper(method), markup_stats.mean, diagnostics.rsquared);
    end
end


function print_cross_method_comparison(results, methods)
    %PRINT_CROSS_METHOD_COMPARISON Compara markups médios entre N métodos
    %
    % Exibe tabela com μ médio por setor para cada método estimado,
    % calculando desvio percentual em relação ao primeiro método da lista.
    
    n_methods = length(methods);
    
    % Coletar setores em comum a todos os métodos com resultados
    common_sectors = results.(method_field(methods{1})).setores;
    for m = 2:n_methods
        res_m = results.(method_field(methods{m}));
        common_sectors = intersect(common_sectors, res_m.setores);
    end
    
    if isempty(common_sectors)
        fprintf('  Nenhum setor em comum entre os métodos.\n\n');
        return;
    end
    
    % Cabeçalho dinâmico
    header_methods = cellfun(@(x) sprintf('%7s', upper(x)), methods, 'UniformOutput', false);
    fprintf('  %-35s  %s\n', 'Setor', strjoin(header_methods, '  '));
    fprintf('  %s\n', repmat('─', 1, 35 + 9 * n_methods));
    
    % Coletar μ médio por setor e método
    means_table = zeros(length(common_sectors), n_methods);
    
    for m = 1:n_methods
        res_m = results.(method_field(methods{m}));
        for s = 1:length(common_sectors)
            idx_s = find(strcmp(res_m.setores, common_sectors{s}), 1);
            if ~isempty(idx_s)
                means_table(s, m) = res_m.markup_stats{idx_s}.mean;
            end
        end
    end
    
    % Imprimir linhas por setor
    for s = 1:length(common_sectors)
        row_vals = arrayfun(@(v) sprintf('%7.3f', v), means_table(s,:), 'UniformOutput', false);
        fprintf('  %-35s  %s\n', ...
            truncate_str(common_sectors{s}, 35), ...
            strjoin(row_vals, '  '));
    end
    
    % Linha de médias agregadas
    fprintf('  %s\n', repmat('─', 1, 35 + 9 * n_methods));
    agg_vals = arrayfun(@(v) sprintf('%7.3f', v), mean(means_table, 1), 'UniformOutput', false);
    fprintf('  %-35s  %s\n\n', 'MÉDIA AGREGADA', strjoin(agg_vals, '  '));
    
    % Desvios percentuais em relação ao primeiro método (referência)
    ref_method = upper(methods{1});
    fprintf('  Desvio %% em relação ao %s:\n', ref_method);
    for m = 2:n_methods
        delta_pct = (mean(means_table(:,m)) - mean(means_table(:,1))) / ...
                     mean(means_table(:,1)) * 100;
        fprintf('    %s vs %s: %+.1f%%\n', upper(methods{m}), ref_method, delta_pct);
    end
    fprintf('\n');
end


function fname = method_field(method)
    %METHOD_FIELD Converte nome de método em nome de campo válido para struct
    %   '2sls'    → 'x2sls'   (makeValidName prefixa com 'x' por começar com número)
    %   'nls'     → 'nls'     (já válido)
    %   'gmm_acf' → 'gmm_acf' (já válido)
    fname = matlab.lang.makeValidName(method);
end
