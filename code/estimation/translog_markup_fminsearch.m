%% TRANSLOG MARKUP ESTIMATION - VERSÃO FMINSEARCH (NLS)
% Estimação via Mínimos Quadrados Não-Lineares usando fminsearch
% 
% Esta versão utiliza otimização direta dos parâmetros da função translog
% ao invés da abordagem 2SLS em dois estágios.
%
% Autores: Vitor Gomes, Fabio Souza, M Lima
% Data: Março 2025
%
% METODOLOGIA:
%   1. Especificar função de produção translog
%   2. Minimizar soma de quadrados dos resíduos via fminsearch
%   3. Calcular markups usando parâmetros estimados
%   4. Bootstrap para erros-padrão

%% ========================================================================
% CONFIGURAÇÕES INICIAIS
% =========================================================================

clearvars;
close all;
clc;

% Configurações
config.max_markup = 10;              
config.confidence_level = 0.95;      
config.n_bootstrap = 100;            % Número de réplicas bootstrap para EP
config.use_bootstrap = true;         % Calcular EP via bootstrap?
config.verbose = true;               
config.optim_display = 'iter';       % 'off', 'final', 'iter'
config.max_iter = 5000;              % Máximo de iterações para fminsearch

% Caminhos
paths.input_data = 'data/processed/panel_data.csv';
paths.output_dir = 'results/';
paths.figures_dir = 'figures/';

if ~exist(paths.output_dir, 'dir'), mkdir(paths.output_dir); end
if ~exist(paths.figures_dir, 'dir'), mkdir(paths.figures_dir); end

fprintf('========================================\n');
fprintf('ESTIMAÇÃO TRANSLOG - MÉTODO FMINSEARCH\n');
fprintf('========================================\n\n');

%% ========================================================================
% 1. CARREGAR E PREPARAR DADOS
% =========================================================================

data = readtable(paths.input_data);
fprintf('   ✓ Dados carregados: %d observações\n', height(data));

% Preparar dados
[data_prep, prep_stats] = prepare_data_nls(data);

fprintf('   ✓ Observações válidas: %d/%d (%.1f%%)\n', ...
        prep_stats.n_valid, prep_stats.n_total, prep_stats.valid_pct);
fprintf('   ✓ Empresas: %d | Setores: %d\n', ...
        prep_stats.n_firms, prep_stats.n_sectors);

