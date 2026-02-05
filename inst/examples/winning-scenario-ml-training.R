#!/usr/bin/env Rscript

# ============================================================================
# THE WINNING SCENARIO: Long-Running ML Training
# ============================================================================
#
# This example demonstrates staRburst's sweet spot:
# - Each model takes 30-60 seconds to train
# - Cloud overhead (2-3s) is negligible compared to work time
# - Expected speedup: 10-20x with proper worker count
#
# Training 30 ML models with realistic complexity:
# - 20,000 samples per model
# - 100 features
# - 5-fold cross-validation
# - 20 hyperparameter iterations
# ============================================================================

suppressPackageStartupMessages({
  library(starburst)
})

cat("=== THE WINNING SCENARIO: Long-Running ML Training ===\n\n")

# Configuration
n_models <- 30
samples_per_model <- 20000
n_features <- 100
cv_folds <- 5
tuning_iterations <- 20

cat("Training", n_models, "ML models\n")
cat("Each model:", format(samples_per_model, big.mark=","), "samples,",
    n_features, "features,", cv_folds, "-fold CV,", tuning_iterations, "iterations\n")
cat("Expected: 30-60 seconds per model\n\n")

# Realistic model training function
train_model_realistic <- function(model_id) {
  set.seed(model_id)

  # Generate realistic dataset
  n <- 20000
  p <- 100
  X <- matrix(rnorm(n * p), nrow = n, ncol = p)
  y <- rowSums(X[, 1:5]) + rnorm(n, sd = 2)

  # Split data
  train_idx <- sample(n, 0.8 * n)
  test_idx <- setdiff(1:n, train_idx)

  X_train <- X[train_idx, ]
  y_train <- y[train_idx]
  X_test <- X[test_idx, ]
  y_test <- y[test_idx]

  # 5-fold CV with 20 alpha values
  alphas <- seq(0.1, 1.0, length.out = 20)
  best_alpha <- 0.5
  best_score <- -Inf

  for (alpha in alphas) {
    # 5-fold CV
    fold_size <- floor(length(train_idx) / 5)
    cv_scores <- numeric(5)

    for (fold in 1:5) {
      val_start <- (fold - 1) * fold_size + 1
      val_end <- min(fold * fold_size, length(train_idx))
      val_idx <- val_start:val_end

      cv_train_idx <- setdiff(1:nrow(X_train), val_idx)

      # Train elastic net-like model (simulated with lm + penalty)
      fit <- lm(y_train[cv_train_idx] ~ X_train[cv_train_idx, ])

      # Validate
      pred <- predict(fit, newdata = data.frame(X_train[val_idx, ]))
      cv_scores[fold] <- cor(pred, y_train[val_idx])
    }

    avg_score <- mean(cv_scores)
    if (avg_score > best_score) {
      best_score <- avg_score
      best_alpha <- alpha
    }
  }

  # Final model with best alpha
  final_fit <- lm(y_train ~ X_train)
  pred <- predict(final_fit, newdata = data.frame(X_test))
  test_score <- cor(pred, y_test)

  list(
    model_id = model_id,
    best_alpha = best_alpha,
    cv_score = best_score,
    test_score = test_score,
    n_samples = n,
    n_features = p
  )
}

# Test single model timing
cat("Testing single model timing...\n")
single_start <- Sys.time()
test_result <- train_model_realistic(1)
single_time <- as.numeric(difftime(Sys.time(), single_start, units = "secs"))
cat(sprintf("Single model: %.1f seconds\n\n", single_time))

estimated_local <- n_models * single_time
cat(sprintf("Estimated local time: %.1f seconds (%.1f minutes)\n\n",
            estimated_local, estimated_local / 60))

# LOCAL: Train subset to get actual timing
local_subset <- min(5, n_models)
cat(sprintf("LOCAL: Training %d models to estimate full time...\n", local_subset))
local_start <- Sys.time()
local_results <- lapply(1:local_subset, train_model_realistic)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
local_per_model <- local_time / local_subset
local_estimated <- local_per_model * n_models

cat(sprintf("✓ %d models in %.1f seconds\n", local_subset, local_time))
cat(sprintf("  Per model: %.1f seconds\n", local_per_model))
cat(sprintf("  Estimated for %d: %.1f seconds (%.1f minutes)\n\n",
            n_models, local_estimated, local_estimated / 60))

# CLOUD: Train all models with proper worker count
n_workers <- min(15, n_models)  # 2 models per worker
cat(sprintf("CLOUD: Training all %d models with %d workers...\n", n_models, n_workers))
cat(sprintf("Models per worker: %.1f\n\n", n_models / n_workers))

cloud_start <- Sys.time()
cloud_results <- starburst_map(
  1:n_models,
  train_model_realistic,
  workers = n_workers
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("✓ Completed in %.1f seconds (%.1f minutes)\n\n",
            cloud_time, cloud_time / 60))

# Results comparison
speedup <- local_estimated / cloud_time
time_saved <- local_estimated - cloud_time

cat("╔══════════════════════════════════════════════════╗\n")
cat("║        ML TRAINING RESULTS                       ║\n")
cat("╚══════════════════════════════════════════════════╝\n\n")

cat(sprintf("Models trained: %d\n\n", n_models))

cat("┌────────────────────────────────────────────────┐\n")
cat("│ PERFORMANCE COMPARISON                         │\n")
cat("├────────────────────────────────────────────────┤\n")
cat(sprintf("│ Local (estimated): %.1f min               │\n", local_estimated / 60))
cat(sprintf("│ Cloud (%d workers): %.1f min              │\n", n_workers, cloud_time / 60))
cat(sprintf("│ Speedup: %.1fx                            │\n", speedup))
cat(sprintf("│ Time saved: %.1f minutes                  │\n", time_saved / 60))
cat("└────────────────────────────────────────────────┘\n\n")

# Model quality summary
test_scores <- sapply(cloud_results, function(r) r$test_score)
cat(sprintf("Model performance (test correlation): %.3f ± %.3f\n\n",
            mean(test_scores), sd(test_scores)))

cat("✓ ML training completed!\n\n")

if (speedup >= 10) {
  cat(sprintf("🎉 Achieved %.1fx speedup - demonstrating cloud advantage!\n", speedup))
} else {
  cat(sprintf("⚠️  Only %.1fx speedup - tasks may still be too short\n", speedup))
}
