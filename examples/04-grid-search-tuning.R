#!/usr/bin/env Rscript
# Hyperparameter Grid Search
#
# Performs grid search over hyperparameters for model tuning.
# Demonstrates: Many model fits with cross-validation (CPU-intensive).

library(furrr)

# Only load starburst if using AWS
use_starburst <- Sys.getenv("USE_STARBURST", "FALSE") == "TRUE"
if (use_starburst) {
  library(starburst)
}

# Generate synthetic dataset for binary classification
set.seed(123)
n_samples <- 1000

generate_dataset <- function() {
  x1 <- rnorm(n_samples)
  x2 <- rnorm(n_samples)
  x3 <- rnorm(n_samples)
  x4 <- rnorm(n_samples)

  # True relationship with some non-linearity
  y_prob <- plogis(
    0.5 * x1 +
    0.8 * x2 +
    -0.3 * x3 +
    0.6 * x1 * x2 +
    rnorm(n_samples, 0, 0.5)
  )

  data.frame(
    x1 = x1,
    x2 = x2,
    x3 = x3,
    x4 = x4,  # Irrelevant feature
    y = rbinom(n_samples, 1, y_prob)
  )
}

# Simple regularized logistic regression (for demo purposes)
# In practice, use glmnet, xgboost, etc.
fit_model <- function(data, lambda, features) {
  # Select features
  X <- as.matrix(data[, features, drop = FALSE])
  y <- data$y

  # Add intercept
  X <- cbind(1, X)

  # Initialize coefficients
  beta <- rep(0, ncol(X))

  # Simple gradient descent with L2 regularization
  learning_rate <- 0.01
  n_iterations <- 100

  for (iter in 1:n_iterations) {
    # Predicted probabilities
    pred <- plogis(X %*% beta)

    # Gradient with L2 penalty
    gradient <- t(X) %*% (pred - y) / length(y) + lambda * c(0, beta[-1])

    # Update
    beta <- beta - learning_rate * gradient
  }

  list(beta = beta, features = features, lambda = lambda)
}

# Cross-validation
cv_score <- function(data, lambda, features, n_folds = 5) {
  n <- nrow(data)
  fold_size <- n %/% n_folds
  fold_ids <- sample(rep(1:n_folds, length.out = n))

  fold_scores <- numeric(n_folds)

  for (fold in 1:n_folds) {
    # Split data
    train_data <- data[fold_ids != fold, ]
    test_data <- data[fold_ids == fold, ]

    # Fit model
    model <- fit_model(train_data, lambda, features)

    # Predict on test set
    X_test <- as.matrix(test_data[, features, drop = FALSE])
    X_test <- cbind(1, X_test)
    pred_prob <- plogis(X_test %*% model$beta)
    pred_class <- as.integer(pred_prob > 0.5)

    # Accuracy
    fold_scores[fold] <- mean(pred_class == test_data$y)
  }

  mean(fold_scores)
}

# Grid search function
evaluate_hyperparameters <- function(param_id, data, lambda, features) {
  score <- cv_score(data, lambda, features)

  list(
    param_id = param_id,
    lambda = lambda,
    features = paste(features, collapse = ","),
    n_features = length(features),
    cv_score = score
  )
}

# Configuration
n_workers <- as.integer(Sys.getenv("STARBURST_WORKERS", "50"))

cat("Hyperparameter Grid Search\n")
cat("===========================\n")

# Generate dataset
cat("Generating dataset...\n")
data <- generate_dataset()
cat("  Samples:", nrow(data), "\n")
cat("  Features:", ncol(data) - 1, "\n")
cat("  Classes:", paste(table(data$y), collapse = " / "), "\n")
cat("\n")

# Define grid
lambda_values <- c(0.001, 0.01, 0.1, 1.0)
feature_combinations <- list(
  c("x1", "x2", "x3", "x4"),      # All features
  c("x1", "x2", "x3"),             # Drop irrelevant
  c("x1", "x2"),                    # Key features only
  c("x1", "x2", "x3", "x4")        # Duplicate for larger grid
)

# Create parameter grid
param_grid <- expand.grid(
  lambda = lambda_values,
  features_idx = 1:length(feature_combinations),
  stringsAsFactors = FALSE
)
param_grid$features <- lapply(param_grid$features_idx,
                              function(i) feature_combinations[[i]])

n_combinations <- nrow(param_grid)

cat("Grid Search Configuration:\n")
cat("  Lambda values:", length(lambda_values), "\n")
cat("  Feature sets:", length(feature_combinations), "\n")
cat("  Total combinations:", n_combinations, "\n")
cat("  CV folds: 5\n")
cat("  Mode:", if(use_starburst) paste("AWS Fargate (", n_workers, "workers)") else "Local\n")
cat("\n")

# Set up execution plan
if (use_starburst) {
  cat("Setting up staRburst...\n")
  plan(future_starburst, workers = n_workers)
} else {
  cat("Using local sequential execution...\n")
  plan(sequential)
}

# Run grid search
cat("Running grid search...\n")
start_time <- Sys.time()

results <- future_map(
  1:n_combinations,
  ~evaluate_hyperparameters(
    param_id = .x,
    data = data,
    lambda = param_grid$lambda[.x],
    features = param_grid$features[[.x]]
  ),
  .options = furrr_options(seed = TRUE),
  .progress = TRUE
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Extract results
cv_scores <- sapply(results, function(x) x$cv_score)
best_idx <- which.max(cv_scores)
best_result <- results[[best_idx]]

cat("\n")
cat("Grid Search Results\n")
cat("===================\n")
cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n", elapsed, elapsed/60))
cat(sprintf("Time per configuration: %.1f seconds\n", elapsed / n_combinations))
cat("\n")
cat("Best Model:\n")
cat(sprintf("  Lambda: %.4f\n", best_result$lambda))
cat(sprintf("  Features: %s\n", best_result$features))
cat(sprintf("  CV Accuracy: %.3f\n", best_result$cv_score))
cat("\n")
cat("Top 5 Configurations:\n")
top_indices <- order(cv_scores, decreasing = TRUE)[1:min(5, length(cv_scores))]
for (i in top_indices) {
  r <- results[[i]]
  cat(sprintf("  %.3f | lambda=%.4f | features=%s\n",
              r$cv_score, r$lambda, r$features))
}

# Save results
output_file <- sprintf("grid-search-results-%s.rds",
                       if(use_starburst) "aws" else "local")
saveRDS(list(
  results = results,
  elapsed = elapsed,
  mode = if(use_starburst) "aws" else "local",
  workers = if(use_starburst) n_workers else 1,
  best_params = best_result,
  timestamp = Sys.time()
), output_file)

cat("\nResults saved to:", output_file, "\n")
