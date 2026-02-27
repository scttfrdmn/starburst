## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup, eval=FALSE--------------------------------------------------------
# library(starburst)

## ----data, eval=FALSE---------------------------------------------------------
# set.seed(42)
# 
# # Variant A (control)
# n_a <- 10000
# conversions_a <- 850
# variant_a <- c(rep(1, conversions_a), rep(0, n_a - conversions_a))
# 
# # Variant B (treatment)
# n_b <- 10000
# conversions_b <- 920
# variant_b <- c(rep(1, conversions_b), rep(0, n_b - conversions_b))
# 
# # Observed difference
# observed_diff <- mean(variant_b) - mean(variant_a)
# cat(sprintf("Observed conversion rates:\n"))
# cat(sprintf("  Variant A: %.2f%%\n", mean(variant_a) * 100))
# cat(sprintf("  Variant B: %.2f%%\n", mean(variant_b) * 100))
# cat(sprintf("  Difference: %.2f%% (%.1f%% relative lift)\n",
#             observed_diff * 100,
#             (observed_diff / mean(variant_a)) * 100))

## ----bootstrap-fn, eval=FALSE-------------------------------------------------
# bootstrap_iteration <- function(iter, data_a, data_b) {
#   # Resample with replacement
#   n_a <- length(data_a)
#   n_b <- length(data_b)
# 
#   sample_a <- sample(data_a, n_a, replace = TRUE)
#   sample_b <- sample(data_b, n_b, replace = TRUE)
# 
#   # Calculate metrics
#   rate_a <- mean(sample_a)
#   rate_b <- mean(sample_b)
#   diff <- rate_b - rate_a
#   relative_lift <- diff / rate_a
# 
#   list(
#     iteration = iter,
#     rate_a = rate_a,
#     rate_b = rate_b,
#     diff = diff,
#     relative_lift = relative_lift,
#     b_wins = diff > 0
#   )
# }

## ----local, eval=FALSE--------------------------------------------------------
# n_bootstrap_local <- 1000
# 
# cat(sprintf("Running %d bootstrap iterations locally...\n", n_bootstrap_local))
# local_start <- Sys.time()
# 
# local_results <- lapply(
#   1:n_bootstrap_local,
#   bootstrap_iteration,
#   data_a = variant_a,
#   data_b = variant_b
# )
# 
# local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
# cat(sprintf("✓ Completed in %.2f seconds\n\n", local_time))

## ----cloud, eval=FALSE--------------------------------------------------------
# n_bootstrap <- 10000
# 
# cat(sprintf("Running %d bootstrap iterations on AWS...\n", n_bootstrap))
# 
# results <- starburst_map(
#   1:n_bootstrap,
#   bootstrap_iteration,
#   data_a = variant_a,
#   data_b = variant_b,
#   workers = 25,
#   cpu = 1,
#   memory = "2GB"
# )

## ----analysis, eval=FALSE-----------------------------------------------------
# # Extract metrics
# diffs <- sapply(results, function(x) x$diff)
# relative_lifts <- sapply(results, function(x) x$relative_lift)
# b_wins <- sapply(results, function(x) x$b_wins)
# 
# # Calculate confidence intervals
# ci_95 <- quantile(diffs, c(0.025, 0.975))
# ci_99 <- quantile(diffs, c(0.005, 0.995))
# 
# # Probability that B is better than A
# prob_b_wins <- mean(b_wins) * 100
# 
# # Print results
# cat("\n=== Bootstrap Results (10,000 iterations) ===\n\n")
# cat(sprintf("Observed difference: %.2f%%\n", observed_diff * 100))
# cat(sprintf("\n95%% Confidence Interval: [%.2f%%, %.2f%%]\n",
#             ci_95[1] * 100, ci_95[2] * 100))
# cat(sprintf("99%% Confidence Interval: [%.2f%%, %.2f%%]\n",
#             ci_99[1] * 100, ci_99[2] * 100))
# cat(sprintf("\nProbability that B > A: %.1f%%\n", prob_b_wins))
# 
# # Statistical significance
# if (ci_95[1] > 0) {
#   cat("\n✓ Result is statistically significant at 95% confidence level\n")
#   cat("  (95% CI does not include zero)\n")
# } else {
#   cat("\n✗ Result is NOT statistically significant at 95% confidence level\n")
#   cat("  (95% CI includes zero)\n")
# }
# 
# # Relative lift analysis
# cat(sprintf("\nRelative lift: %.1f%%\n",
#             median(relative_lifts) * 100))
# cat(sprintf("95%% CI for relative lift: [%.1f%%, %.1f%%]\n",
#             quantile(relative_lifts, 0.025) * 100,
#             quantile(relative_lifts, 0.975) * 100))

## ----viz, eval=FALSE----------------------------------------------------------
# # Create histogram
# hist(diffs * 100,
#      breaks = 50,
#      main = "Bootstrap Distribution of Conversion Rate Difference",
#      xlab = "Difference in Conversion Rate (percentage points)",
#      col = "lightblue",
#      border = "white")
# 
# # Add reference lines
# abline(v = 0, col = "red", lwd = 2, lty = 2)
# abline(v = ci_95 * 100, col = "darkblue", lwd = 2, lty = 2)
# abline(v = observed_diff * 100, col = "darkgreen", lwd = 2)
# 
# # Add legend
# legend("topright",
#        c("Observed difference", "Zero (no effect)", "95% CI"),
#        col = c("darkgreen", "red", "darkblue"),
#        lwd = 2,
#        lty = c(1, 2, 2))

## ----multi-metric, eval=FALSE-------------------------------------------------
# bootstrap_all_metrics <- function(iter, data_a, data_b) {
#   n_a <- length(data_a)
#   n_b <- length(data_b)
# 
#   sample_a <- sample(data_a, n_a, replace = TRUE)
#   sample_b <- sample(data_b, n_b, replace = TRUE)
# 
#   # Multiple metrics
#   rate_a <- mean(sample_a)
#   rate_b <- mean(sample_b)
#   se_a <- sd(sample_a) / sqrt(n_a)
#   se_b <- sd(sample_b) / sqrt(n_b)
# 
#   list(
#     diff_rate = rate_b - rate_a,
#     relative_lift = (rate_b - rate_a) / rate_a,
#     z_score = (rate_b - rate_a) / sqrt(se_a^2 + se_b^2),
#     effect_size = (rate_b - rate_a) / sqrt((var(sample_a) + var(sample_b)) / 2)
#   )
# }
# 
# # Run multi-metric bootstrap
# multi_results <- starburst_map(
#   1:10000,
#   bootstrap_all_metrics,
#   data_a = variant_a,
#   data_b = variant_b,
#   workers = 25
# )

## ----eval=FALSE---------------------------------------------------------------
# system.file("examples/bootstrap.R", package = "starburst")

## ----eval=FALSE---------------------------------------------------------------
# source(system.file("examples/bootstrap.R", package = "starburst"))

