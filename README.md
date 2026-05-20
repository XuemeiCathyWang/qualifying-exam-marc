# Ideal-Point Estimation in the 20th German Bundestag

Qualifying examination submission by Bastian Koch.

**Website:** https://bastiankoch.github.io/qualifying_exam_yy/

## Overview

Analysis of roll-call voting behaviour in the 20th German Bundestag (2021–2025)
using two approaches to ideal-point estimation: Singular Value Decomposition and
Bayesian 2-Parameter Logistic Item Response Theory.

## Repository structure

| Path | Contents |
|---|---|
| `analysis.R` | Full analysis script (Parts i–v) |
| `index.qmd` | Quarto source for the website |
| `_quarto.yml` | Quarto project config |
| `docs/` | Rendered website (served by GitHub Pages) |
| `output/` | Plots, tables, and interactive HTML widgets |
| `models/` | Fitted brms IRT model (`fit_bundestag_2pl.rds`) |
| `Data/` | Roll-call vote matrix and codebook |
| `ai_interaction_log.md` | Log of AI assistance used during the exam |

## Parts

- **i** — Double-mean imputation of the vote matrix
- **ii** — SVD of the imputed matrix: legislator scalings, extreme votes, variance explained
- **iii** — Double-centered SVD and comparison with Part ii
- **iv** — Bayesian 2PL IRT model fit with brms (Bürkner 2021)
- **v** — Substantive claim: FDP's centrist position evaluated via posterior ordering probabilities

## Dependencies

R packages: `tidyverse`, `brms`, `tidybayes`, `plotly`, `ggridges`, `htmlwidgets`, `patchwork`
