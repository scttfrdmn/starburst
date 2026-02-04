#!/usr/bin/env Rscript
#
# Parallel Grid Search Example
#
# This script demonstrates parallel hyperparameter tuning with cross-validation.
# It evaluates 81 parameter combinations for a gradient boosting model.
#
# Usage:
#   Rscript grid-search.R
#   # or from R:
#   source(system.file("examples/grid-search.R", package = "starburst"))

library(starburst)

cat("=== Parallel Grid Search for Hyperparameter Tuning ===\n\n")

# Generate synthetic classification data
set.seed(2024)

n_samples <- 10000
n_features <- 20

cat("Generating synthetic dataset...\n")

X <- matrix(rnorm(n_samples * n_features), nrow = n_samples)
colnames(X) <- paste0("feature_", 1:n_features)

true_coef <- rnorm(n_features)
linear_pred <- X %*% true_coef
prob <- 1 / (1 + exp(-linear_pred))
y <- rbinom(n_samples, 1, prob)

# Train/test split
train_idx <- sample(1:n_samples, 0.7 * n_samples)
X_train <- X[train_idx, ]
y_train <- y[train_idx]
X_test <- X[-train_idx, ]
y_test <- y[-train_idx]

cat(sprintf("✓ Dataset created:\n"))
cat(sprintf("  Training samples: %s\n", format(length(y_train), big.mark = ",")))
cat(sprintf("  Test samples: %s\n", format(length(y_test), big.mark = ",")))
cat(sprintf("  Features: %d\n", n_features))
cat(sprintf("  Class balance: %.1f%% / %.1f%%\n\n",
            mean(y_train) * 100, (1 - mean(y_train)) * 100))

# Define parameter grid
param_grid <- expand.grid(
  learning_rate = c(0.01, 0.05, 0.1),
  max_depth = c(3, 5, 7),
  subsample = c(0.6, 0.8, 1.0),
  min_child_weight = c(1, 3, 5),
  stringsAsFactors = FALSE
)

cat(sprintf("Grid search space:\n"))
cat(sprintf("  Total combinations: %d\n", nrow(param_grid)))
cat(sprintf("  With 5-fold CV: %d model fits\n\n", nrow(param_grid) * 5))

# Simplified GBM training (mock implementation)
train_gbm <- function(X, y, params, n_trees = 50) {
  n <- nrow(X)
  pred <- rep(mean(y), n)

  complexity_factor <- params$max_depth * (1 / params$learning_rate) *
                      (1 / params$subsample)
  training_time <- 0.001 * complexity_factor * n_trees

  Sys.sleep(min(training_time, 5))

  pred <- pred + rnorm(n, 0, 0.1)
  pred <- pmin(pmax(pred, 0), 1)

  list(predictions = pred, params = params)
}

# Cross-validation function
cv_evaluate <- function(param_row, X_data, y_data, n_folds = 5) {
  params <- as.list(param_row)

  n <- nrow(X_data)
  fold_size <- floor(n / n_folds)
  fold_indices <- sample(rep(1:n_folds, length.out = n))

  cv_scores <- numeric(n_folds)

  for (fold in 1:n_folds) {
    val_idx <- which(fold_indices == fold)
    train_idx <- which(fold_indices != fold)

    X_fold_train <- X_data[train_idx, , drop = FALSE]
    y_fold_train <- y_data[train_idx]
    X_fold_val <- X_data[val_idx, , drop = FALSE]
    y_fold_val <- y_data[val_idx]

    model <- train_gbm(X_fold_train, y_fold_train, params)

    baseline_accuracy <- mean(y_fold_val == round(mean(y_fold_train)))

    param_quality <- (params$learning_rate >= 0.05) * 0.02 +
                    (params$max_depth >= 5) * 0.02 +
                    (params$subsample >= 0.8) * 0.01 +
                    rnorm(1, 0, 0.02)

    accuracy <- min(baseline_accuracy + param_quality, 1.0)
    cv_scores[fold] <- accuracy
  }

  list(
    params = params,
    mean_cv_score = mean(cv_scores),
    std_cv_score = sd(cv_scores),
    cv_scores = cv_scores
  )
}

# Local benchmark (10 combinations)
cat("Running local benchmark (10 parameter combinations)...\n")
set.seed(999)
sample_params <- param_grid[sample(1:nrow(param_grid), 10), ]

local_start <- Sys.time()

local_results <- lapply(1:nrow(sample_params), function(i) {
  cv_evaluate(sample_params[i, ], X_train, y_train, n_folds = 5)
})

local_time <- as.numeric(difftime(Sys.time(), local_start, units = "mins"))

cat(sprintf("✓ Completed in %.2f minutes\n", local_time))
cat(sprintf("  Average time per combination: %.1f seconds\n",
            local_time * 60 / nrow(sample_params)))
cat(sprintf("  Estimated time for full grid: %.1f minutes\n\n",
            local_time * nrow(param_grid) / nrow(sample_params)))

# Cloud execution
n_workers <- 27

cat(sprintf("Running grid search (%d combinations) on %d workers...\n",
            nrow(param_grid), n_workers))

cloud_start <- Sys.time()

results <- starburst_map(
  1:nrow(param_grid),
  function(i) cv_evaluate(param_grid[i, ], X_train, y_train, n_folds = 5),
  workers = n_workers,
  cpu = 2,
  memory = "4GB"
)

cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "mins"))

cat(sprintf("\n✓ Completed in %.2f minutes\n\n", cloud_time))

# Extract results
cv_scores <- sapply(results, function(x) x$mean_cv_score)
cv_stds <- sapply(results, function(x) x$std_cv_score)

results_df <- cbind(param_grid,
                   mean_score = cv_scores,
                   std_score = cv_stds)

results_df <- results_df[order(-results_df$mean_score), ]

# Print results
cat("=== Grid Search Results ===\n\n")
cat(sprintf("Total combinations evaluated: %d\n", nrow(results_df)))
cat(sprintf("Best CV score: %.4f (± %.4f)\n\n",
            results_df$mean_score[1], results_df$std_score[1]))

cat("=== Best Hyperparameters ===\n")
cat(sprintf("  Learning rate: %.3f\n", results_df$learning_rate[1]))
cat(sprintf("  Max depth: %d\n", results_df$max_depth[1]))
cat(sprintf("  Subsample: %.2f\n", results_df$subsample[1]))
cat(sprintf("  Min child weight: %d\n\n", results_df$min_child_weight[1]))

cat("=== Top 5 Parameter Combinations ===\n")
for (i in 1:5) {
  cat(sprintf("\n%d. Score: %.4f (± %.4f)\n", i,
              results_df$mean_score[i], results_df$std_score[i]))
  cat(sprintf("   lr=%.3f, depth=%d, subsample=%.2f, min_child=%d\n",
              results_df$learning_rate[i],
              results_df$max_depth[i],
              results_df$subsample[i],
              results_df$min_child_weight[i]))
}

# Parameter impact analysis
cat("\n=== Parameter Impact Analysis ===\n")
for (param in c("learning_rate", "max_depth", "subsample", "min_child_weight")) {
  param_means <- aggregate(mean_score ~ get(param),
                          data = results_df, FUN = mean)
  names(param_means)[1] <- param

  cat(sprintf("\n%s:\n", param))
  for (i in 1:nrow(param_means)) {
    cat(sprintf("  %s: %.4f\n",
                param_means[i, 1],
                param_means[i, 2]))
  }
}

# Performance comparison
cat("\n=== Performance Comparison ===\n\n")
estimated_local <- local_time * nrow(param_grid) / nrow(sample_params)
speedup <- estimated_local / cloud_time
cat(sprintf("Local (estimated): %.1f minutes\n", estimated_local))
cat(sprintf("Cloud (%d workers): %.2f minutes\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

cat("\n✓ Done!\n")
