#!/usr/bin/env Rscript
#
# Bootstrap Confidence Intervals Example
#
# This script demonstrates parallel bootstrap resampling for A/B test analysis.
# It calculates robust confidence intervals for conversion rate differences.
#
# Usage:
#   Rscript bootstrap.R
#   # or from R:
#   source(system.file("examples/bootstrap.R", package = "starburst"))

library(starburst)

cat("=== Bootstrap Confidence Intervals for A/B Testing ===\n\n")

# Generate A/B test data
set.seed(42)

# Variant A (control)
n_a <- 10000
conversions_a <- 850
variant_a <- c(rep(1, conversions_a), rep(0, n_a - conversions_a))

# Variant B (treatment)
n_b <- 10000
conversions_b <- 920
variant_b <- c(rep(1, conversions_b), rep(0, n_b - conversions_b))

# Observed statistics
observed_rate_a <- mean(variant_a)
observed_rate_b <- mean(variant_b)
observed_diff <- observed_rate_b - observed_rate_a
observed_lift <- (observed_diff / observed_rate_a) * 100

cat("Observed conversion rates:\n")
cat(sprintf("  Variant A: %.2f%%\n", observed_rate_a * 100))
cat(sprintf("  Variant B: %.2f%%\n", observed_rate_b * 100))
cat(sprintf("  Difference: %.2f%% (%.1f%% relative lift)\n\n",
            observed_diff * 100, observed_lift))

# Bootstrap function
bootstrap_iteration <- function(iter, data_a, data_b) {
  # Resample with replacement
  n_a <- length(data_a)
  n_b <- length(data_b)

  sample_a <- sample(data_a, n_a, replace = TRUE)
  sample_b <- sample(data_b, n_b, replace = TRUE)

  # Calculate metrics
  rate_a <- mean(sample_a)
  rate_b <- mean(sample_b)
  diff <- rate_b - rate_a
  relative_lift <- diff / rate_a

  list(
    iteration = iter,
    rate_a = rate_a,
    rate_b = rate_b,
    diff = diff,
    relative_lift = relative_lift,
    b_wins = diff > 0
  )
}

# Local benchmark (1000 iterations)
cat("Running local benchmark (1,000 bootstrap iterations)...\n")
local_start <- Sys.time()
local_results <- lapply(
  1:1000,
  bootstrap_iteration,
  data_a = variant_a,
  data_b = variant_b
)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
cat(sprintf("  Estimated time for 10,000: %.1f seconds\n\n",
            local_time * 10))

# Cloud execution
n_bootstrap <- 10000
n_workers <- 25

cat(sprintf("Running %d bootstrap iterations on %d workers...\n",
            n_bootstrap, n_workers))

cloud_start <- Sys.time()
results <- starburst_map(
  1:n_bootstrap,
  bootstrap_iteration,
  data_a = variant_a,
  data_b = variant_b,
  workers = n_workers,
  cpu = 1,
  memory = "2GB"
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("\n✓ Completed in %.1f seconds\n\n", cloud_time))

# Extract metrics
diffs <- sapply(results, function(x) x$diff)
relative_lifts <- sapply(results, function(x) x$relative_lift)
b_wins <- sapply(results, function(x) x$b_wins)

# Calculate confidence intervals
ci_95 <- quantile(diffs, c(0.025, 0.975))
ci_99 <- quantile(diffs, c(0.005, 0.995))
prob_b_wins <- mean(b_wins) * 100

# Print results
cat("=== Bootstrap Results ===\n\n")
cat(sprintf("Bootstrap iterations: %d\n\n", n_bootstrap))
cat(sprintf("Observed difference: %.2f%%\n\n", observed_diff * 100))
cat(sprintf("95%% Confidence Interval: [%.2f%%, %.2f%%]\n",
            ci_95[1] * 100, ci_95[2] * 100))
cat(sprintf("99%% Confidence Interval: [%.2f%%, %.2f%%]\n\n",
            ci_99[1] * 100, ci_99[2] * 100))
cat(sprintf("Probability that B > A: %.1f%%\n\n", prob_b_wins))

# Statistical significance
if (ci_95[1] > 0) {
  cat("✓ Result is statistically significant at 95% confidence level\n")
  cat("  (95% CI does not include zero)\n\n")
} else {
  cat("✗ Result is NOT statistically significant at 95% confidence level\n")
  cat("  (95% CI includes zero)\n\n")
}

# Relative lift
cat(sprintf("Median relative lift: %.1f%%\n",
            median(relative_lifts) * 100))
cat(sprintf("95%% CI for relative lift: [%.1f%%, %.1f%%]\n\n",
            quantile(relative_lifts, 0.025) * 100,
            quantile(relative_lifts, 0.975) * 100))

# Performance comparison
cat("=== Performance Comparison ===\n\n")
speedup <- (local_time * 10) / cloud_time
cat(sprintf("Local (estimated): %.1f seconds\n", local_time * 10))
cat(sprintf("Cloud (%d workers): %.1f seconds\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

# Visualization (if in interactive session)
if (interactive()) {
  hist(diffs * 100,
       breaks = 50,
       main = "Bootstrap Distribution of Conversion Rate Difference",
       xlab = "Difference in Conversion Rate (percentage points)",
       col = "lightblue",
       border = "white")
  abline(v = 0, col = "red", lwd = 2, lty = 2)
  abline(v = ci_95 * 100, col = "darkblue", lwd = 2, lty = 2)
  abline(v = observed_diff * 100, col = "darkgreen", lwd = 2)
  legend("topright",
         c("Observed difference", "Zero (no effect)", "95% CI"),
         col = c("darkgreen", "red", "darkblue"),
         lwd = 2,
         lty = c(1, 2, 2))
}

cat("\n✓ Done!\n")
