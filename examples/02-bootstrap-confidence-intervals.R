#!/usr/bin/env Rscript
# Bootstrap Confidence Intervals
#
# Calculates bootstrap confidence intervals for statistical estimates.
# Demonstrates: Many independent resampling operations with moderate compute.

library(furrr)

# Only load starburst if using AWS
use_starburst <- Sys.getenv("USE_STARBURST", "FALSE") == "TRUE"
if (use_starburst) {
  library(starburst)
}

# Generate sample data: effect of treatment on outcome
set.seed(42)
n_control <- 100
n_treatment <- 120

data <- data.frame(
  group = c(rep("control", n_control), rep("treatment", n_treatment)),
  outcome = c(
    rnorm(n_control, mean = 50, sd = 10),      # Control group
    rnorm(n_treatment, mean = 55, sd = 12)     # Treatment group (5 pt effect)
  )
)

# Bootstrap function: resample and calculate treatment effect
bootstrap_treatment_effect <- function(i, data) {
  # Resample with replacement
  n <- nrow(data)
  boot_indices <- sample(1:n, n, replace = TRUE)
  boot_data <- data[boot_indices, ]

  # Calculate means for each group
  control_mean <- mean(boot_data$outcome[boot_data$group == "control"])
  treatment_mean <- mean(boot_data$outcome[boot_data$group == "treatment"])

  # Treatment effect
  effect <- treatment_mean - control_mean

  # Also calculate Cohen's d (standardized effect size)
  control_sd <- sd(boot_data$outcome[boot_data$group == "control"])
  treatment_sd <- sd(boot_data$outcome[boot_data$group == "treatment"])
  pooled_sd <- sqrt((control_sd^2 + treatment_sd^2) / 2)
  cohens_d <- effect / pooled_sd

  list(
    effect = effect,
    cohens_d = cohens_d,
    control_mean = control_mean,
    treatment_mean = treatment_mean
  )
}

# Configuration
n_bootstrap <- 10000
n_workers <- as.integer(Sys.getenv("STARBURST_WORKERS", "50"))

cat("Bootstrap Confidence Intervals\n")
cat("==============================\n")
cat("Sample size:", nrow(data), "(", n_control, "control,", n_treatment, "treatment)\n")
cat("Bootstrap samples:", n_bootstrap, "\n")
cat("Mode:", if(use_starburst) paste("AWS Fargate (", n_workers, "workers)") else "Local\n")
cat("\n")

# Observed statistics
obs_control <- mean(data$outcome[data$group == "control"])
obs_treatment <- mean(data$outcome[data$group == "treatment"])
obs_effect <- obs_treatment - obs_control

cat("Observed Statistics:\n")
cat(sprintf("  Control mean: %.2f\n", obs_control))
cat(sprintf("  Treatment mean: %.2f\n", obs_treatment))
cat(sprintf("  Treatment effect: %.2f\n", obs_effect))
cat("\n")

# Set up execution plan
if (use_starburst) {
  cat("Setting up staRburst...\n")
  plan(future_starburst, workers = n_workers)
} else {
  cat("Using local sequential execution...\n")
  plan(sequential)
}

# Run bootstrap
cat("Running bootstrap...\n")
start_time <- Sys.time()

boot_results <- future_map(
  1:n_bootstrap,
  ~bootstrap_treatment_effect(.x, data),
  .options = furrr_options(seed = TRUE),
  .progress = TRUE
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Extract estimates
boot_effects <- sapply(boot_results, function(x) x$effect)
boot_cohens_d <- sapply(boot_results, function(x) x$cohens_d)

# Calculate confidence intervals
ci_level <- 0.95
alpha <- 1 - ci_level
ci_lower <- quantile(boot_effects, alpha/2)
ci_upper <- quantile(boot_effects, 1 - alpha/2)

ci_d_lower <- quantile(boot_cohens_d, alpha/2)
ci_d_upper <- quantile(boot_cohens_d, 1 - alpha/2)

cat("\n")
cat("Bootstrap Results\n")
cat("=================\n")
cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n", elapsed, elapsed/60))
cat("\n")
cat(sprintf("Treatment Effect: %.2f\n", obs_effect))
cat(sprintf("  Bootstrap SE: %.2f\n", sd(boot_effects)))
cat(sprintf("  95%% CI: [%.2f, %.2f]\n", ci_lower, ci_upper))
cat("\n")
cat(sprintf("Cohen's d: %.2f\n", obs_effect / sd(data$outcome)))
cat(sprintf("  95%% CI: [%.2f, %.2f]\n", ci_d_lower, ci_d_upper))
cat("\n")

# Statistical significance
p_value <- mean(boot_effects <= 0)
cat(sprintf("P-value (effect <= 0): %.4f\n", p_value))
cat("Interpretation:", if(p_value < 0.05) "Significant effect" else "Not significant", "\n")

# Save results
output_file <- sprintf("bootstrap-results-%s.rds",
                       if(use_starburst) "aws" else "local")
saveRDS(list(
  boot_results = boot_results,
  elapsed = elapsed,
  mode = if(use_starburst) "aws" else "local",
  workers = if(use_starburst) n_workers else 1,
  ci = c(ci_lower, ci_upper),
  timestamp = Sys.time()
), output_file)

cat("\nResults saved to:", output_file, "\n")
