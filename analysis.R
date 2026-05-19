# =============================================================================
# Qualifying Exam — Ideal-Point Estimation in the 20th German Bundestag
# Parts i–v: Double-mean imputation, SVD, double-centering, Bayesian 2PL IRT,
# and a substantive claim using the posterior distribution.
# =============================================================================

# Run once to install all required packages
# install.packages(c("tidyverse", "brms", "tidybayes", "plotly",
#                    "patchwork", "ggridges", "htmlwidgets"))

library(tidyverse)
library(brms)
library(tidybayes)
library(plotly)
library(patchwork)
library(htmlwidgets)

theme_set(theme_minimal(base_size = 13))

# Official German party colours
party_colours <- c(
  "AfD"                        = "#009EE0",
  "CDU/CSU"                    = "#32302E",
  "SPD"                        = "#E3000F",
  "BÜNDNIS 90/DIE GRÜNEN"      = "#64A12D",
  "FDP"                        = "#E5A100",
  "DIE LINKE"                  = "#BE3075",
  "fraktionslos"               = "#808080"
)

if (!dir.exists("models")) dir.create("models")
if (!dir.exists("output")) dir.create("output")

save_plot <- function(p, filename, width = 9, height = 5.5) {
  ggsave(file.path("output", filename), p,
         width = width, height = height, dpi = 150)
  invisible(p)
}

# -----------------------------------------------------------------------------
# Data
# -----------------------------------------------------------------------------
votes_wide <- read_csv("Data/bundestag_wp132_votes_clean.csv",
                       show_col_types = FALSE)
votes_long <- read_csv("Data/bundestag_wp132_votes_clean_long.csv",
                       show_col_types = FALSE)
codebook   <- read_csv("Data/bundestag_wp132_vote_codebook.csv",
                       show_col_types = FALSE)

# Vote matrix: legislators (rows) × votes (columns)
X <- votes_wide |>
  select(starts_with("v")) |>
  as.matrix()
rownames(X) <- votes_wide$name

cat("Dimensions:", nrow(X), "legislators ×", ncol(X), "votes\n")
cat("Missing entries:", sum(is.na(X)), "/", prod(dim(X)),
    sprintf("(%.1f%%)\n", 100 * mean(is.na(X))))


# =============================================================================
# Part i — Double-Mean Imputation
# =============================================================================
# Fill each NA with: row mean + column mean − grand mean.

row_means_obs <- rowMeans(X, na.rm = TRUE)
col_means_obs <- colMeans(X, na.rm = TRUE)
grand_mean_obs <- mean(X, na.rm = TRUE)

X_imp <- X
na_pos <- which(is.na(X), arr.ind = TRUE)
X_imp[na_pos] <- row_means_obs[na_pos[, 1]] +
                 col_means_obs[na_pos[, 2]] -
                 grand_mean_obs

stopifnot(!anyNA(X_imp))
cat("\nPart i — imputation complete. Grand mean:", round(grand_mean_obs, 3), "\n")


# =============================================================================
# Part ii — SVD of the Imputed Matrix
# =============================================================================
svd_imp <- svd(X_imp)
U_imp   <- svd_imp$u   # legislator scalings  (n_legislators × n_dims)
D_imp   <- svd_imp$d   # singular values
V_imp   <- svd_imp$v   # vote scalings         (n_votes × n_dims)

# Sign convention: AfD (far-right) gets a positive first-dimension score.
afd_rows <- which(votes_wide$party == "AfD")
if (mean(U_imp[afd_rows, 1]) < 0) {
  U_imp[, 1] <- -U_imp[, 1]
  V_imp[, 1] <- -V_imp[, 1]
}

leg_svd_imp <- tibble(
  name  = votes_wide$name,
  party = votes_wide$party,
  dim1  = U_imp[, 1],
  dim2  = U_imp[, 2]
)

vote_svd_imp <- tibble(
  vote_column = colnames(X),
  dim1        = V_imp[, 1],
  dim2        = V_imp[, 2]
) |> left_join(codebook, by = "vote_column")

var_explained_imp <- D_imp^2 / sum(D_imp^2)
cat("\nPart ii — SVD (imputed matrix)\n")
cat("Variance explained by dim1:", round(var_explained_imp[1], 3), "\n")
cat("Variance explained by dim2:", round(var_explained_imp[2], 3), "\n")

write_csv(leg_svd_imp,  "output/ii_legislator_scalings_imputed.csv")
write_csv(vote_svd_imp, "output/ii_vote_scalings_imputed.csv")

# --- (a) Legislator scalings on dim 1 ----------------------------------------
p_leg_imp <- leg_svd_imp |>
  mutate(party = fct_reorder(party, dim1, median)) |>
  ggplot(aes(dim1, party, colour = party)) +
  geom_jitter(height = 0.15, alpha = 0.6, size = 1.5) +
  stat_summary(fun = median, geom = "point", shape = 18, size = 4,
               colour = "black") +
  scale_colour_manual(values = party_colours, guide = "none") +
  labs(title = "Part ii (a) — Legislator scalings, Dimension 1",
       subtitle = "SVD of double-mean-imputed matrix",
       x = "First left singular vector", y = NULL)

print(p_leg_imp)
save_plot(p_leg_imp, "ii_a_legislator_dim1_imputed.png")

# --- (b) Most and least extreme votes on dim 1 --------------------------------
n_extreme <- 10
extreme_votes_imp <- vote_svd_imp |>
  slice_max(abs(dim1), n = n_extreme * 2) |>
  arrange(dim1) |>
  mutate(label     = str_trunc(poll_label, 55),
         direction = if_else(dim1 > 0, "pro-opposition", "pro-coalition"))

cat("\nMost negative dim1 votes (coalition-aligned):\n")
extreme_votes_imp |> slice_head(n = n_extreme) |>
  select(vote_column, label, dim1, accepted) |> print(n = Inf)

cat("\nMost positive dim1 votes (opposition-aligned):\n")
extreme_votes_imp |> slice_tail(n = n_extreme) |>
  select(vote_column, label, dim1, accepted) |> print(n = Inf)

write_csv(extreme_votes_imp, "output/ii_b_extreme_votes_imputed.csv")

p_votes_imp <- vote_svd_imp |>
  slice_max(abs(dim1), n = 20) |>
  mutate(label = str_trunc(poll_label, 50),
         label = fct_reorder(label, dim1)) |>
  ggplot(aes(dim1, label,
             fill = if_else(dim1 > 0, "Opposition-leaning", "Coalition-leaning"))) +
  geom_col() +
  scale_fill_manual(values = c("Coalition-leaning" = "#4477AA",
                               "Opposition-leaning" = "#BB4444"),
                    name = NULL) +
  labs(title = "Part ii (b) — Most extreme votes on Dimension 1",
       x = "First right singular vector", y = NULL) +
  theme(legend.position = "bottom")

print(p_votes_imp)
save_plot(p_votes_imp, "ii_b_extreme_votes_imputed.png", height = 7)

# --- (c) Second dimension: meaningful or noise? --------------------------------
p_leg_imp_d2 <- leg_svd_imp |>
  mutate(party = fct_reorder(party, dim2, median)) |>
  ggplot(aes(dim2, party, colour = party)) +
  geom_jitter(height = 0.15, alpha = 0.6, size = 1.5) +
  stat_summary(fun = median, geom = "point", shape = 18, size = 4,
               colour = "black") +
  scale_colour_manual(values = party_colours, guide = "none") +
  labs(title = "Part ii (c) — Legislator scalings, Dimension 2",
       x = "Second left singular vector", y = NULL)

print(p_leg_imp_d2)
save_plot(p_leg_imp_d2, "ii_c_legislator_dim2_imputed.png")

# Interactive scatter: dim1 vs dim2
p_scatter_imp <- leg_svd_imp |>
  plot_ly(x = ~dim1, y = ~dim2, color = ~party,
          colors = party_colours,
          text  = ~paste0(name, "<br>", party),
          hoverinfo = "text",
          type = "scatter", mode = "markers",
          marker = list(size = 6, opacity = 0.7)) |>
  layout(title = "Legislator ideal points — SVD (imputed matrix)",
         xaxis = list(title = "Dimension 1"),
         yaxis = list(title = "Dimension 2"))

print(p_scatter_imp)
saveWidget(p_scatter_imp, file.path("output", "ii_c_scatter_interactive.html"),
           selfcontained = TRUE)

# --- (d) Variance explained ---------------------------------------------------
var_df_imp <- tibble(
  dim      = seq_along(D_imp),
  var_prop = D_imp^2 / sum(D_imp^2),
  cum_var  = cumsum(var_prop)
) |> filter(dim <= 20)

write_csv(var_df_imp, "output/ii_d_variance_explained.csv")

p_var_imp <- var_df_imp |>
  ggplot(aes(dim, var_prop)) +
  geom_col(fill = "#4477AA") +
  geom_line(aes(y = cum_var), colour = "grey30", linetype = "dashed") +
  geom_point(aes(y = cum_var), colour = "grey30") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Part ii (d) — Variance explained by each SVD dimension",
       subtitle = sprintf("Dim 1 explains %.1f%% of variance",
                          100 * var_explained_imp[1]),
       x = "Dimension", y = "Proportion of variance")

print(p_var_imp)
save_plot(p_var_imp, "ii_d_variance_explained.png", width = 7, height = 5)


# =============================================================================
# Part iii — Double-Centered Matrix
# =============================================================================
# X̃ᵢⱼ = Xᵢⱼ − X̄ᵢ. − X̄.ⱼ + X̄..
# Applied to the imputed (complete) matrix to guarantee exact zero means.

M1   <- sweep(X_imp, 1, rowMeans(X_imp), "-")  # subtract row means
X_dc <- sweep(M1,    2, colMeans(M1),    "-")  # subtract adjusted col means

cat("\nPart iii — double-centering\n")
cat("Max |row mean| after centering:", max(abs(rowMeans(X_dc))), "\n")
cat("Max |col mean| after centering:", max(abs(colMeans(X_dc))), "\n")

svd_dc <- svd(X_dc)
U_dc   <- svd_dc$u
D_dc   <- svd_dc$d
V_dc   <- svd_dc$v

if (mean(U_dc[afd_rows, 1]) < 0) {
  U_dc[, 1] <- -U_dc[, 1]
  V_dc[, 1] <- -V_dc[, 1]
}

leg_svd_dc <- tibble(
  name  = votes_wide$name,
  party = votes_wide$party,
  dim1  = U_dc[, 1],
  dim2  = U_dc[, 2]
)

vote_svd_dc <- tibble(
  vote_column = colnames(X),
  dim1        = V_dc[, 1],
  dim2        = V_dc[, 2]
) |> left_join(codebook, by = "vote_column")

var_explained_dc <- D_dc^2 / sum(D_dc^2)
cat("Variance explained by dim1 (double-centered):", round(var_explained_dc[1], 3), "\n")

write_csv(leg_svd_dc,  "output/iii_legislator_scalings_doublecentered.csv")
write_csv(vote_svd_dc, "output/iii_vote_scalings_doublecentered.csv")

p_leg_dc <- leg_svd_dc |>
  mutate(party = fct_reorder(party, dim1, median)) |>
  ggplot(aes(dim1, party, colour = party)) +
  geom_jitter(height = 0.15, alpha = 0.6, size = 1.5) +
  stat_summary(fun = median, geom = "point", shape = 18, size = 4,
               colour = "black") +
  scale_colour_manual(values = party_colours, guide = "none") +
  labs(title = "Part iii — Legislator scalings, Dimension 1 (double-centered)",
       x = "First left singular vector", y = NULL)

print(p_leg_dc)
save_plot(p_leg_dc, "iii_legislator_dim1_doublecentered.png")

# Comparison: imputed vs. double-centered dim1
compare_svd <- leg_svd_imp |>
  select(name, party, dim1_imp = dim1) |>
  left_join(leg_svd_dc |> select(name, dim1_dc = dim1), by = "name")

cat("Correlation between dim1 (imputed) and dim1 (double-centered):",
    round(cor(compare_svd$dim1_imp, compare_svd$dim1_dc), 4), "\n")

write_csv(compare_svd, "output/iii_svd_comparison.csv")

p_compare_svd <- compare_svd |>
  ggplot(aes(dim1_imp, dim1_dc, colour = party)) +
  geom_point(alpha = 0.6, size = 1.5) +
  geom_abline(linetype = "dashed", colour = "grey40") +
  scale_colour_manual(values = party_colours, name = "Party") +
  labs(title = "Part iii — SVD Dimension 1: imputed vs. double-centered",
       x = "Imputed matrix — Dim 1",
       y = "Double-centered matrix — Dim 1")

print(p_compare_svd)
save_plot(p_compare_svd, "iii_svd_comparison.png", width = 7, height = 6)


# =============================================================================
# Part iv — Bayesian 2-Parameter Logistic IRT (brms)
# =============================================================================
# Model: Pr(y_ij = 1) = logit⁻¹(α_i (θ_j − β_i))
#   θ_j : latent ideal point of legislator j
#   β_i : difficulty (location) of vote i
#   α_i : discrimination of vote i
#
# Reparameterised as in Bürkner (2021):
#   y ~ exp(logalpha) * eta
#   eta      ~ 1 + (1 | i | vote_id) + (1 | legislator_id)
#   logalpha ~ 1 + (1 | i | vote_id)
#
# Priors (weakly informative, following Bürkner 2021 defaults):
#   eta intercept          ~ N(0, 5)
#   logalpha intercept     ~ N(0, 1)
#   SD of person effects   ~ constant(1)   [scale identification]
#   SD of vote difficulty  ~ N(0, 3)
#   SD of vote disc.       ~ N(0, 1)

votes_long_prep <- votes_long |>
  mutate(
    legislator_id = as.factor(name),
    vote_id       = as.factor(vote_column)
  )

formula_2pl <- bf(
  y        ~ exp(logalpha) * eta,
  eta      ~ 1 + (1 | i | vote_id) + (1 | legislator_id),
  logalpha ~ 1 + (1 | i | vote_id),
  nl       = TRUE
)

prior_2pl <-
  prior("normal(0, 5)", class = "b",  nlpar = "eta") +
  prior("normal(0, 1)", class = "b",  nlpar = "logalpha") +
  prior("constant(1)", class = "sd",  group = "legislator_id", nlpar = "eta") +
  prior("normal(0, 3)", class = "sd", group = "vote_id",       nlpar = "eta") +
  prior("normal(0, 1)", class = "sd", group = "vote_id",       nlpar = "logalpha")

# brms saves the fitted model to disk and skips refitting on re-runs.
# Expect ~1–3 hours on a laptop with 4 cores.
fit_2pl <- brm(
  formula = formula_2pl,
  data    = votes_long_prep,
  family  = bernoulli("logit"),
  prior   = prior_2pl,
  chains  = 4,
  cores   = 4,
  iter    = 2000,
  warmup  = 1000,
  seed    = 42,
  file    = "models/fit_bundestag_2pl"
)

cat("\n--- Model summary ---\n")
print(summary(fit_2pl))

# Extract person random effects (ideal points θ_j)
person_re <- ranef(fit_2pl)$legislator_id

ideal_pts <- tibble(
  name     = rownames(person_re[,, "eta_Intercept"]),
  estimate = person_re[, "Estimate",   "eta_Intercept"],
  lo       = person_re[, "Q2.5",       "eta_Intercept"],
  hi       = person_re[, "Q97.5",      "eta_Intercept"],
  err      = person_re[, "Est.Error",  "eta_Intercept"]
) |>
  left_join(votes_wide |> select(name, party), by = "name")

# Same sign convention: AfD positive
if (mean(ideal_pts$estimate[ideal_pts$party == "AfD"]) < 0) {
  ideal_pts <- ideal_pts |>
    mutate(across(c(estimate, lo, hi), ~ -.x))
}

write_csv(ideal_pts, "output/iv_ideal_points_irt.csv")

# Interactive ideal-point plot
p_irt_scatter <- ideal_pts |>
  plot_ly(
    x         = ~estimate,
    y         = ~party,
    color     = ~party,
    colors    = party_colours,
    text      = ~paste0(name, "<br>", party,
                        "<br>θ̂ = ", round(estimate, 2),
                        " [", round(lo, 2), ", ", round(hi, 2), "]"),
    hoverinfo = "text",
    type      = "scatter",
    mode      = "markers",
    marker    = list(size = 5, opacity = 0.6)
  ) |>
  layout(
    title      = "Part iv — Posterior ideal points (2PL IRT)",
    xaxis      = list(title = "Ideal point θ̂ (posterior mean)"),
    yaxis      = list(title = NULL),
    showlegend = FALSE
  )

print(p_irt_scatter)
saveWidget(p_irt_scatter,
           file.path("output", "iv_idealpoints_interactive.html"),
           selfcontained = TRUE)

# Static version
p_irt_static <- ideal_pts |>
  mutate(party = fct_reorder(party, estimate, median)) |>
  ggplot(aes(estimate, party, colour = party)) +
  geom_jitter(height = 0.15, alpha = 0.5, size = 1.5) +
  stat_summary(fun = median, geom = "point", shape = 18, size = 4,
               colour = "black") +
  scale_colour_manual(values = party_colours, guide = "none") +
  labs(title = "Part iv — Posterior ideal points (2PL IRT)",
       x = "Ideal point θ̂ (posterior mean)", y = NULL)

print(p_irt_static)
save_plot(p_irt_static, "iv_idealpoints_static.png")

# Comparison: IRT vs. SVD
compare_all <- ideal_pts |>
  select(name, party, irt = estimate) |>
  left_join(leg_svd_imp |> select(name, svd_imp = dim1), by = "name") |>
  left_join(leg_svd_dc  |> select(name, svd_dc  = dim1), by = "name")

cat("\nCorrelations between methods:\n")
cat("IRT vs. SVD (imputed):        ", round(cor(compare_all$irt, compare_all$svd_imp), 4), "\n")
cat("IRT vs. SVD (double-centered):", round(cor(compare_all$irt, compare_all$svd_dc),  4), "\n")
cat("SVD imputed vs. double-centered:", round(cor(compare_all$svd_imp, compare_all$svd_dc), 4), "\n")

write_csv(compare_all, "output/iv_method_comparison.csv")

p_compare_all <- compare_all |>
  ggplot(aes(svd_imp, irt, colour = party)) +
  geom_point(alpha = 0.6, size = 1.5) +
  geom_smooth(method = "lm", se = FALSE, colour = "grey30", linewidth = 0.7) +
  scale_colour_manual(values = party_colours, name = "Party") +
  labs(title = "Part iv — IRT ideal points vs. SVD Dimension 1",
       x = "SVD Dim 1 (imputed matrix)",
       y = "IRT posterior mean (θ̂)")

print(p_compare_all)
save_plot(p_compare_all, "iv_irt_vs_svd.png", width = 7, height = 6)


# =============================================================================
# Part v — Substantive Claim Using the Posterior Distribution
# =============================================================================
# Claim: The FDP occupies a distinct position between the SPD/Grüne bloc and
# the CDU/CSU — consistent with its role as the liberal pivot in the Ampel
# coalition.  We evaluate this using the full posterior, not just point estimates.

draws_long <- fit_2pl |>
  spread_draws(r_legislator_id[legislator_id, term]) |>
  filter(term == "eta_Intercept") |>
  left_join(
    votes_wide |> select(name, party) |> mutate(legislator_id = name),
    by = "legislator_id"
  )

afd_sign <- draws_long |>
  filter(party == "AfD") |>
  summarise(m = mean(r_legislator_id)) |>
  pull(m)

if (afd_sign < 0) {
  draws_long <- draws_long |>
    mutate(r_legislator_id = -r_legislator_id)
}

party_draws <- draws_long |>
  group_by(.draw, party) |>
  summarise(party_mean = mean(r_legislator_id), .groups = "drop")

comparisons <- list(
  c("FDP",      "SPD"),
  c("FDP",      "BÜNDNIS 90/DIE GRÜNEN"),
  c("FDP",      "CDU/CSU"),
  c("CDU/CSU",  "AfD"),
  c("DIE LINKE","SPD")
)

cat("\nPart v — Posterior probabilities of ideological ordering:\n")
prob_results <- map_dfr(comparisons, function(pair) {
  left_party  <- pair[1]
  right_party <- pair[2]
  prob <- party_draws |>
    filter(party %in% pair) |>
    pivot_wider(names_from = party, values_from = party_mean) |>
    summarise(p = mean(.data[[left_party]] > .data[[right_party]])) |>
    pull(p)
  cat(sprintf("P(%s > %s) = %.1f%%\n", left_party, right_party, 100 * prob))
  tibble(left = left_party, right = right_party, prob = prob)
})

write_csv(prob_results, "output/v_ordering_probabilities.csv")

parties_of_interest <- c("DIE LINKE", "BÜNDNIS 90/DIE GRÜNEN", "SPD",
                          "FDP", "CDU/CSU", "AfD")

p_posterior <- party_draws |>
  filter(party %in% parties_of_interest) |>
  mutate(party = factor(party, levels = parties_of_interest)) |>
  ggplot(aes(party_mean, party, fill = party)) +
  ggridges::geom_density_ridges(alpha = 0.7, scale = 1.2,
                                 quantile_lines = TRUE,
                                 quantiles = c(0.025, 0.975)) +
  scale_fill_manual(values = party_colours, guide = "none") +
  labs(
    title    = "Part v — Posterior distribution of party-level mean ideal points",
    subtitle = "Vertical lines at 2.5% and 97.5% quantiles",
    x        = "Mean ideal point (posterior draw)",
    y        = NULL
  )

print(p_posterior)
save_plot(p_posterior, "v_party_posteriors.png", height = 6)

party_summary <- party_draws |>
  filter(party %in% parties_of_interest) |>
  group_by(party) |>
  summarise(
    mean = mean(party_mean),
    lo   = quantile(party_mean, 0.025),
    hi   = quantile(party_mean, 0.975),
    .groups = "drop"
  ) |>
  arrange(mean)

cat("\nParty posterior summary (sorted left to right):\n")
print(party_summary, digits = 3)

write_csv(party_summary, "output/v_party_summary.csv")

cat("\nAll outputs saved to output/\n")
