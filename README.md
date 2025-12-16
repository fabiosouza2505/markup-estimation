# Estimação de Markups - Empresas Brasileiras Listadas
Implementação da metodologia **De Loecker & Warzynski (2012)** para estimação de markups\nde empresas listadas na B3, com função de produção Translog.
## 📊 Sobre o Projeto
Este projeto estima markups (poder de mercado) de empresas brasileiras usando:
- **Função de Produção:** Translog (flexível, dois insumos)
- **Metodologia:** Ackerberg-Caves-Frazer (2015) + 2SLS
- **Dados:** Painel trimestral 1990-2025, empresas listadas B3
- **Setores:** Indústria, serviços, utilities
## 📁 Estrutura do Repositório
```
markup-estimation-matlab/
│
├── code/                          
# 💻 Código MATLAB
│   ├── estimation/
# Scripts de estimação
│   │   ├── translog_markup_estimation.m
# 2SLS (principal)
│   │   ├── translog_markup_fminsearch.m
# NLS alternativo
│   │   └── functions/
# Funções auxiliares
│   ├── analysis/
# Análise de resultados
│   │   └── analyze_markup_results.m
│   └── tests/
# Testes e validação
│       ├── exemplo_uso_rapido.m
│       └── demo_2sls_vs_fminsearch.m\n
│
├── data/
# 📊 Dados (não versionados)
│   ├── raw/
# Dados brutos da Economática
│   └── processed/
# Painel limpo (panel_data.csv)
│
├── results/
# 📈 Outputs (não versionados)
│   ├── tables/
# Tabelas CSV e LaTeX
│   ├── figures/
# Gráficos PNG/PDF
│   └── estimates/
# Parâmetros estimados (.mat)
│
├── docs/
# 📚 Documentação
│   ├── README_MATLAB.md
# Manual completo
│   ├── COMPARACAO_2SLS_vs_FMINSEARCH.md
│   └── VALIDACAO_PYTHON_MATLAB.md
│
├── paper/
# 📄 Artigo (LaTeX)
│
├── .gitignore
# Git ignore rules
├── LICENSE
# Licença MIT
└── README.md
# Este arquivo
```\n\n
## 🚀 Como Usar
### Pré-requisitos
- MATLAB R2020b ou superior
- Statistics and Machine Learning Toolbox
- Dados processados em `data/processed/panel_data.csv`
### Setup Inicial
```matlab
% Adicionar caminhos do projeto\naddpath(genpath('code'));\nsavepath;
```
### Estimação Principal (2SLS)
```matlab
cd code/estimation\ntranslog_markup_estimation
```
**Outputs:**
- `results/elasticities_by_sector.csv`
- Elasticidades estimadas
- `results/markups_panel.csv`
- Série de markups
- `results/estimation_diagnostics.mat`
- Workspace completo
### Análise de Resultados
```matlab
cd code/analysis\nanalyze_markup_results
```
**Outputs:**
- 6 figuras em `results/figures/`
- Tabelas LaTeX em `results/tables/`
### Testes
```matlab
cd code/tests\nexemplo_uso_rapido           % Teste com dados sintéticos\ndemo_2sls_vs_fminsearch      % Comparação metodológica
```
## 📖 Documentação
Ver pasta `docs/` para documentação completa:
- **Manual Completo:** `docs/README_MATLAB.md`
- **Comparação Metodológica:** `docs/COMPARACAO_2SLS_vs_FMINSEARCH.md`
- **Validação Python-MATLAB:** `docs/VALIDACAO_PYTHON_MATLAB.md`
## 🔬 Metodologia
### Função de Produção Translog\n\n
A receita da firma segue uma função de produção flexível:
```
log(Q_it) = β₀ + β_v·log(V_it) + β_k·log(K_it) + \n            ½·β_vv·[log(V_it)]² + ½·β_kk·[log(K_it)]² + \n            β_vk·log(V_it)·log(K_it) + ω_it + ε_it
```
Onde:
- Q_it = Receita da firma i no período t
- V_it = Insumo variável (COGS + despesas administrativas)
- K_it = Capital (imobilizado + investimentos)
- ω_it = Produtividade não-observada
### Markup
O markup é calculado como:
```
μ_it = θ_V,it / α_V,it
```
Onde:
- θ_V,it = Elasticidade do insumo variável
- α_V,it = Share do insumo na receita
## 👥 Autores
**Prof. Vitor Gomes** - Orientador, Departamento de Economia, UnB
**Fabio Souza** - Mestrando em Economia, UnB
## 📚 Referências
- De Loecker, J., & Warzynski, F. (2012). Markups and firm-level export status. *American Economic Review*, 102(6), 2437-2471.
- Ackerberg, D. A., Caves, K., & Frazer, G. (2015). Identification properties of recent production function estimators. *Econometrica*, 83(6), 2411-2451.
## 📄 Licença\n\nEste projeto está licenciado sob a Licença MIT - veja [LICENSE](LICENSE) para detalhes.
---
**Última atualização:** 16/12/2025\n
