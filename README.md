# Estimação de Markups - Empresas Brasileiras Listadas
Implementação da metodologia **De Loecker & Warzynski (2012)** para estimação de markups\nde empresas listadas na B3, com função de produção Translog.\n\n
## 📊 Sobre o Projeto\n\n
Este projeto estima markups (poder de mercado) de empresas brasileiras usando:\n
- **Função de Produção:** Translog (flexível, dois insumos)\n
- **Metodologia:** Ackerberg-Caves-Frazer (2015) + 2SLS\n
- **Dados:** Painel trimestral 1990-2025, empresas listadas B3\n
- **Setores:** Indústria, serviços, utilities\n\n
## 📁 Estrutura do Repositório\n\n
```\nmarkup-estimation-matlab/\n│\n├── code/                          
# 💻 Código MATLAB\n│   ├── estimation/
# Scripts de estimação\n│   │   ├── translog_markup_estimation.m
# 2SLS (principal)\n│   │   ├── translog_markup_fminsearch.m
# NLS alternativo\n│   │   └── functions/
# Funções auxiliares\n│   ├── analysis/
# Análise de resultados\n│   │   └── analyze_markup_results.m\n│   └── tests/
# Testes e validação\n│       ├── exemplo_uso_rapido.m\n│       └── demo_2sls_vs_fminsearch.m\n│\n├── data/
# 📊 Dados (não versionados)\n│   ├── raw/
# Dados brutos da Economática\n│   └── processed/
# Painel limpo (panel_data.csv)\n│\n├── results/
# 📈 Outputs (não versionados)\n│   ├── tables/
# Tabelas CSV e LaTeX\n│   ├── figures/
# Gráficos PNG/PDF\n│   └── estimates/
# Parâmetros estimados (.mat)\n│\n├── docs/
# 📚 Documentação\n│   ├── README_MATLAB.md
# Manual completo\n│   ├── COMPARACAO_2SLS_vs_FMINSEARCH.md\n│   └── VALIDACAO_PYTHON_MATLAB.md\n│\n├── paper/
# 📄 Artigo (LaTeX)\n│\n├── .gitignore
# Git ignore rules\n├── LICENSE
# Licença MIT\n└── README.md
# Este arquivo\n```\n\n
## 🚀 Como Usar\n\n
### Pré-requisitos\n\n- MATLAB R2020b ou superior\n- Statistics and Machine Learning Toolbox\n- Dados processados em `data/processed/panel_data.csv`\n\n
### Setup Inicial\n\n
```matlab\n% Adicionar caminhos do projeto\naddpath(genpath('code'));\nsavepath;\n```\n\n
### Estimação Principal (2SLS)\n\n```matlab\ncd code/estimation\ntranslog_markup_estimation\n```\n\n**Outputs:**\n- `results/elasticities_by_sector.csv` - Elasticidades estimadas\n- `results/markups_panel.csv` - Série de markups\n- `results/estimation_diagnostics.mat` - Workspace completo\n\n### Análise de Resultados\n\n```matlab\ncd code/analysis\nanalyze_markup_results\n```\n\n**Outputs:**\n- 6 figuras em `results/figures/`\n- Tabelas LaTeX em `results/tables/`\n\n### Testes\n\n```matlab\ncd code/tests\nexemplo_uso_rapido           % Teste com dados sintéticos\ndemo_2sls_vs_fminsearch      % Comparação metodológica\n```\n\n## 📖 Documentação\n\nVer pasta `docs/` para documentação completa:\n- **Manual Completo:** `docs/README_MATLAB.md`\n- **Comparação Metodológica:** `docs/COMPARACAO_2SLS_vs_FMINSEARCH.md`\n- **Validação Python-MATLAB:** `docs/VALIDACAO_PYTHON_MATLAB.md`\n\n## 🔬 Metodologia\n\n### Função de Produção Translog\n\nA receita da firma segue uma função de produção flexível:\n\n```\nlog(Q_it) = β₀ + β_v·log(V_it) + β_k·log(K_it) + \n            ½·β_vv·[log(V_it)]² + ½·β_kk·[log(K_it)]² + \n            β_vk·log(V_it)·log(K_it) + ω_it + ε_it\n```\n\nOnde:\n- Q_it = Receita da firma i no período t\n- V_it = Insumo variável (COGS + despesas administrativas)\n- K_it = Capital (imobilizado + investimentos)\n- ω_it = Produtividade não-observada\n\n### Markup\n\nO markup é calculado como:\n\n```\nμ_it = θ_V,it / α_V,it\n```\n\nOnde:\n- θ_V,it = Elasticidade do insumo variável\n- α_V,it = Share do insumo na receita\n\n## 👥 Autores\n\n- **Fabio Souza** - Mestrando em Economia, UnB\n- **Prof. Vitor Gomes** - Orientador, Departamento de Economia, UnB\n\n## 📚 Referências\n\n- De Loecker, J., & Warzynski, F. (2012). Markups and firm-level export status. *American Economic Review*, 102(6), 2437-2471.\n- Ackerberg, D. A., Caves, K., & Frazer, G. (2015). Identification properties of recent production function estimators. *Econometrica*, 83(6), 2411-2451.\n\n## 📄 Licença\n\nEste projeto está licenciado sob a Licença MIT - veja [LICENSE](LICENSE) para detalhes.\n\n---\n\n**Última atualização:** 16/12/2025\n
