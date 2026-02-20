# Estimação de Markups — Empresas Brasileiras Listadas

Implementação da metodologia **De Loecker & Warzynski (2012)** para estimação de markups
de empresas listadas na B3, com função de produção Translog e validação cross-platform
Python/MATLAB.

## Sobre o Projeto

Este projeto estima markups (poder de mercado) a nível de firma para a indústria brasileira,
utilizando dois métodos de estimação com validação cruzada:

- **Função de Produção:** Translog (dois insumos, elasticidades variáveis por firma)
- **Métodos de Estimação:** 2SLS (variáveis instrumentais) e NLS (benchmark)
- **Dados:** Painel trimestral 1990–2025, empresas listadas na B3
- **Setores:** 8 setores industriais
- **Plataformas:** MATLAB e Python (convergência 0.0% em todas as casas decimais)

### Principais Resultados

| Métrica | Valor |
|---------|-------|
| Markup médio agregado (2SLS) | 1.222 |
| Markup médio agregado (NLS) | 1.199 |
| Diferença cross-method | −1.9% |
| Diferença cross-platform | 0.0% |
| F-estatísticas (instrumentos) | > 2.000 em todos os setores |

## Estrutura do Repositório

```
markup-estimation/
│
├── code/
│   ├── matlab/                         # Implementação MATLAB
│   │   ├── main.m                      # Orquestrador principal (loop método × setor)
│   │   ├── estimate_translog.m         # Dispatcher: roteia para 2SLS ou NLS
│   │   ├── estimate_translog_2sls.m    # Estimação via variáveis instrumentais
│   │   ├── estimate_translog_nls.m     # Estimação via mínimos quadrados não-lineares
│   │   ├── prepare_data.m              # Preparação do painel (logs, shares, validação)
│   │   ├── calculate_markups_from_params_weighted.m  # Cálculo de markups com correção de produtividade
│   │   ├── save_multiple_sectors_results.m           # Export: parâmetros, sumário, diagnósticos
│   │   ├── save_estimation_results.m                 # Export: markups firma-período
│   │   └── group_lag.m                 # Lags respeitando fronteiras de firma no painel
│   │
│   └── python/                         # Implementação Python
│       ├── main.py                     # Script principal
│       └── translog_markup_estimator.py  # Classe de estimação
│
├── data/
│   ├── raw/                            # Dados brutos (Economática)
│   └── processed/                      # Painel limpo (final_data.csv)
│
├── results/
│   ├── 2sls/                           # Resultados do método 2SLS
│   │   ├── translog_parametros.csv     #   Coeficientes estimados por setor
│   │   ├── markup_sumario.csv          #   Estatísticas descritivas dos markups
│   │   ├── diagnosticos.csv            #   R², F-stats, instrumentos
│   │   ├── markups_empresa.csv         #   Markups a nível firma-período
│   │   └── markups_setor_periodo.csv   #   Médias por setor-ano com IC 95%
│   │
│   └── nls/                            # Resultados do método NLS (mesma estrutura)
│
├── docs/                               # Documentação
│   ├── estrategia_estimacao_markups.docx  # Nota técnica (metodologia detalhada)
│   └── VALIDACAO_PYTHON_MATLAB.md         # Relatório de validação cross-platform
│
├── paper/                              # Artigo (LaTeX)
│
├── .gitignore
├── LICENSE                             # MIT
└── README.md
```

## Arquitetura

O projeto utiliza uma arquitetura **funcional** onde o `main.m` orquestra o pipeline
chamando diretamente cada função, sem intermediário de classe:

```
main.m
  │
  ├─ readtable()                    Carregar dados
  ├─ prepare_data()                 Preparar painel (logs, shares, filtros)
  │
  ├─ Loop: método × setor
  │   ├─ estimate_translog()        Dispatcher → _2sls ou _nls
  │   └─ calculate_markups_...()    Elasticidades → markups
  │
  ├─ save_multiple_sectors_results()  CSVs de resumo
  ├─ save_estimation_results()        CSV firma-período
  └─ plot_markup_results()            Plotagem (futuro)
```

O campo `config.methods = {'2sls', 'nls'}` controla quais métodos são executados.
Os resultados são armazenados em subdiretórios separados (`results/2sls/`, `results/nls/`)
e uma comparação cross-method é gerada automaticamente ao final.

## Como Usar

### Pré-requisitos

- MATLAB R2020b ou superior
- Statistics and Machine Learning Toolbox
- Dados processados em `data/processed/final_data.csv`

### Execução

```matlab
% No MATLAB Command Window:
main
```

O script interativo permite escolher entre estimar todos os setores ou um setor específico.
Ambos os métodos (2SLS e NLS) são executados automaticamente.

### Outputs Gerados

Para cada método, são gerados os seguintes arquivos:

| Arquivo | Conteúdo |
|---------|----------|
| `translog_parametros.csv` | Coeficientes β estimados por setor (7 parâmetros) |
| `markup_sumario.csv` | Média ponderada, média simples, mediana, p25, p75, % acima de 1 |
| `diagnosticos.csv` | R² (1º e 2º estágio), RMSE, F-stats, instrumentos fracos |
| `markups_empresa.csv` | Markup, elasticidades e share por firma-período |
| `markups_setor_periodo.csv` | Médias por setor-ano com IC 95% e teste de poder de mercado |

## Metodologia

### Função de Produção Translog

```
log(Q_it) = β₀ + βᵥ·log(V_it) + βₖ·log(K_it)
           + βᵥᵥ·[log(V_it)]² + βₖₖ·[log(K_it)]²
           + βᵥₖ·log(V_it)·log(K_it) + ω_it + ε_it
```

Onde:
- **Q_it** — Receita líquida da firma *i* no período *t*
- **V_it** — Insumo variável (custos operacionais)
- **K_it** — Capital (ativo imobilizado)
- **ω_it** — Produtividade total dos fatores (não observada pelo econometrista)
- **ε_it** — Choque não antecipado / erro de medida

**Nota sobre parametrização:** os coeficientes quadráticos (βᵥᵥ, βₖₖ) multiplicam
diretamente os termos ao quadrado, **sem** o fator ½. A elasticidade é calculada como
`θᵥ = βᵥ + 2·βᵥᵥ·log(V) + βᵥₖ·log(K)`, onde o fator 2 surge da derivação.

### Markup

```
μ_it = θ_V,it / α_V,it
```

- **θ_V,it** — Elasticidade do produto em relação ao insumo variável (estimada)
- **α_V,it** — Share do insumo variável na receita (observado nos dados)

### Método 2SLS (Principal)

O 2SLS corrige a endogeneidade do insumo variável via variáveis instrumentais,
em três fases:

1. **Forma reduzida:** polinômio de grau 3 nos insumos como proxy para produtividade.
   Recupera ω̂_it e ε̂_it.
2. **Lei de movimento:** decompõe ω̂_it em componente previsível (Markov, grau 3) e
   inovação ξ_it.
3. **Equação estrutural:** estima os coeficientes β via 2SLS, usando 18 instrumentos
   (5 lags temporais do insumo variável × 3 transformações + capital + produtividade).

Os lags são construídos respeitando fronteiras de firma no painel (`group_lag`),
evitando contaminação entre firmas distintas.

### Método NLS (Benchmark)

O NLS minimiza diretamente a soma dos quadrados dos resíduos via Nelder-Mead,
sem correção de endogeneidade. Serve como benchmark de robustez e validação
computacional. A produtividade é estimada como resíduo direto da regressão.

## Validação

### Cross-Method (2SLS vs NLS)

| Setor | μ 2SLS | μ NLS | Δ (%) |
|-------|--------|-------|-------|
| Ind. extrativa e agropecuária | 1.512 | 1.489 | −1.5% |
| Alimentos e bebidas | 1.078 | 1.070 | −0.8% |
| Têxteis, vestuário, couro | 1.171 | 1.156 | −1.3% |
| Madeira, celulose, papel | 1.223 | 1.334 | +9.1% |
| Ind. química e petroquímica | 1.027 | 0.943 | −8.1% |
| Metalurgia, siderurgia | 1.424 | 1.336 | −6.2% |
| Máquinas e equipamentos | 1.175 | 1.143 | −2.7% |
| Veículos automotores | 1.168 | 1.124 | −3.8% |
| **Média Agregada** | **1.222** | **1.199** | **−1.9%** |

### Cross-Platform (Python vs MATLAB)

Markups médios ponderados idênticos em todas as 3 casas decimais, para todos os
8 setores. Diferença: **0.0%**.

## Autores

**Prof. Vitor Gomes** — Orientador, Departamento de Economia, UnB

**Fabio Souza** — Mestrando em Economia, UnB

## Referências

- De Loecker, J., & Warzynski, F. (2012). Markups and firm-level export status.
  *American Economic Review*, 102(6), 2437-2471.
- De Loecker, J., Eeckhout, J., & Unger, G. (2020). The rise of market power
  and the macroeconomic implications. *Quarterly Journal of Economics*, 135(2), 561-644.
- Levinsohn, J., & Petrin, A. (2003). Estimating production functions using inputs
  to control for unobservables. *Review of Economic Studies*, 70(2), 317-341.
- Olley, G. S., & Pakes, A. (1996). The dynamics of productivity in the
  telecommunications equipment industry. *Econometrica*, 64(6), 1263-1297.

## Licença

Este projeto está licenciado sob a Licença MIT — veja [LICENSE](LICENSE) para detalhes.

---
**Última atualização:** Fevereiro 2025
