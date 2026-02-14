#!/usr/bin/env Rscript
# Heavy computational benchmarks where AWS burst parallelism dominates

library(starburst)
library(future)
library(future.apply)

# Utility: Get performance cores on Mac
get_performance_cores <- function() {
  if (Sys.info()["sysname"] == "Darwin") {
    p_cores <- suppressWarnings(
      system("sysctl -n hw.perflevel0.logicalcpu 2>/dev/null", intern = TRUE)
    )
    if (length(p_cores) > 0 && !is.na(as.integer(p_cores))) {
      return(as.integer(p_cores))
    }
  }
  return(parallel::detectCores() - 1)
}

# ============================================================================
# BENCHMARK 1: Bayesian MCMC Chains
# ============================================================================
# Multiple independent Markov chains for posterior estimation
# Each chain: 100,000 iterations with expensive likelihood evaluation

run_mcmc_chain <- function(chain_id, n_iter = 100000, n_params = 50) {
  set.seed(chain_id)

  # Complex hierarchical model with expensive likelihood
  log_likelihood <- function(params, data) {
    # Matrix operations to make it expensive
    X <- matrix(rnorm(length(data) * length(params)),
                nrow = length(data), ncol = length(params))
    linear_pred <- X %*% params

    # Negative binomial likelihood (more expensive than normal)
    size <- exp(params[1])
    mu <- exp(linear_pred)
    sum(dnbinom(data, size = size, mu = mu, log = TRUE))
  }

  # Simulate data
  n_obs <- 1000
  data <- rpois(n_obs, lambda = 50)

  # MCMC sampling
  current <- rnorm(n_params)
  samples <- matrix(0, nrow = n_iter, ncol = n_params)
  accept_count <- 0

  for (i in 1:n_iter) {
    proposal <- current + rnorm(n_params, sd = 0.1)

    current_ll <- tryCatch(
      log_likelihood(current, data),
      error = function(e) -Inf
    )
    proposal_ll <- tryCatch(
      log_likelihood(proposal, data),
      error = function(e) -Inf
    )

    # Metropolis-Hastings acceptance
    log_ratio <- proposal_ll - current_ll
    if (is.finite(log_ratio) && log(runif(1)) < log_ratio) {
      current <- proposal
      accept_count <- accept_count + 1
    }

    samples[i, ] <- current
  }

  list(
    chain_id = chain_id,
    samples = samples,
    acceptance_rate = accept_count / n_iter,
    posterior_mean = colMeans(samples[-(1:1000), ])  # Drop burn-in
  )
}

benchmark_mcmc <- function(n_chains = 100, mode = "local-par") {
  cat("\n")
  cat("====================================================================== \n")
  cat("BENCHMARK 1: BAYESIAN MCMC CHAINS\n")
  cat("====================================================================== \n")
  cat(sprintf("Chains: %d (100,000 iterations each, ~3.7 min per chain)\n", n_chains))
  cat(sprintf("Mode: %s\n", mode))
  cat("\n")

  if (mode == "local-seq") {
    plan(sequential)
  } else if (mode == "local-par") {
    n_cores <- get_performance_cores()
    cat(sprintf("Using %d performance cores\n", n_cores))
    plan(multisession, workers = n_cores)
  } else if (mode == "ec2") {
    plan(starburst,
         workers = 100,
         launch_type = "EC2",
         instance_type = "c6a.large")
  }

  start_time <- Sys.time()

  results <- future_lapply(1:n_chains, run_mcmc_chain,
                           future.seed = TRUE)

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat("\n=== RESULTS ===\n")
  cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n",
              elapsed, elapsed / 60))
  cat(sprintf("Chains: %d\n", n_chains))
  cat(sprintf("Avg acceptance rate: %.1f%%\n",
              mean(sapply(results, function(x) x$acceptance_rate)) * 100))
  cat("\n")

  invisible(results)
}

# ============================================================================
# BENCHMARK 2: Bootstrap Resampling with GLM
# ============================================================================
# Thousands of bootstrap samples with expensive model fitting

fit_bootstrap_sample <- function(sample_id, data, n_predictors = 100) {
  set.seed(sample_id)

  # Resample data
  n <- nrow(data)
  indices <- sample(1:n, n, replace = TRUE)
  boot_data <- data[indices, ]

  # Fit complex generalized additive model
  # Using glm with many predictors as proxy for expensive model
  formula_str <- sprintf("y ~ %s",
                        paste0("poly(x", 1:n_predictors, ", 3)",
                               collapse = " + "))
  formula_obj <- as.formula(formula_str)

  # Fit model (this is the expensive part)
  model <- glm(formula_obj, data = boot_data, family = gaussian())

  # Extract coefficients
  list(
    sample_id = sample_id,
    coefficients = coef(model),
    deviance = deviance(model),
    aic = AIC(model)
  )
}

benchmark_bootstrap <- function(n_bootstrap = 1000, mode = "local-par") {
  cat("\n")
  cat("====================================================================== \n")
  cat("BENCHMARK 2: BOOTSTRAP RESAMPLING WITH GLM\n")
  cat("====================================================================== \n")
  cat(sprintf("Bootstrap samples: %d\n", n_bootstrap))
  cat(sprintf("Mode: %s\n", mode))
  cat("\n")

  # Generate synthetic data
  n_obs <- 5000
  n_predictors <- 100

  cat("Generating synthetic dataset...\n")
  data <- as.data.frame(matrix(rnorm(n_obs * n_predictors),
                               nrow = n_obs, ncol = n_predictors))
  names(data) <- paste0("x", 1:n_predictors)
  data$y <- rnorm(n_obs)

  if (mode == "local-seq") {
    plan(sequential)
  } else if (mode == "local-par") {
    n_cores <- get_performance_cores()
    cat(sprintf("Using %d performance cores\n", n_cores))
    plan(multisession, workers = n_cores)
  } else if (mode == "ec2") {
    plan(starburst,
         workers = 100,
         launch_type = "EC2",
         instance_type = "c6a.xlarge")
  }

  cat("Running bootstrap resampling...\n")
  start_time <- Sys.time()

  results <- future_lapply(1:n_bootstrap, fit_bootstrap_sample,
                           data = data, n_predictors = n_predictors,
                           future.seed = TRUE)

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat("\n=== RESULTS ===\n")
  cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n",
              elapsed, elapsed / 60))
  cat(sprintf("Bootstrap samples: %d\n", n_bootstrap))
  cat(sprintf("Avg deviance: %.1f\n",
              mean(sapply(results, function(x) x$deviance))))
  cat("\n")

  invisible(results)
}

# ============================================================================
# BENCHMARK 3: Hyperparameter Grid Search
# ============================================================================
# Train models with different hyperparameters (cross-validation expensive)

train_model_with_params <- function(param_id, X, y, params) {
  set.seed(param_id)

  # Extract hyperparameters
  alpha <- params$alpha
  lambda <- params$lambda
  n_folds <- params$n_folds

  # K-fold cross-validation
  n <- nrow(X)
  fold_ids <- sample(rep(1:n_folds, length.out = n))
  cv_errors <- numeric(n_folds)

  for (fold in 1:n_folds) {
    # Split data
    train_idx <- fold_ids != fold
    test_idx <- fold_ids == fold

    X_train <- X[train_idx, , drop = FALSE]
    y_train <- y[train_idx]
    X_test <- X[test_idx, , drop = FALSE]
    y_test <- y[test_idx]

    # Ridge regression with matrix operations (expensive)
    # Add regularization: (X'X + lambda*I)^-1 X'y
    XtX <- crossprod(X_train)
    Xty <- crossprod(X_train, y_train)
    I <- diag(ncol(X_train))

    # Solve with regularization
    beta <- tryCatch({
      solve(XtX + lambda * I) %*% Xty
    }, error = function(e) {
      matrix(0, nrow = ncol(X_train), ncol = 1)
    })

    # Predict and calculate error
    y_pred <- X_test %*% beta
    cv_errors[fold] <- mean((y_test - y_pred)^2)
  }

  list(
    param_id = param_id,
    alpha = alpha,
    lambda = lambda,
    cv_error = mean(cv_errors),
    cv_se = sd(cv_errors) / sqrt(n_folds)
  )
}

benchmark_hyperparameter_search <- function(n_params = 100, mode = "local-par") {
  cat("\n")
  cat("====================================================================== \n")
  cat("BENCHMARK 3: HYPERPARAMETER GRID SEARCH\n")
  cat("====================================================================== \n")
  cat(sprintf("Parameter combinations: %d\n", n_params))
  cat(sprintf("Mode: %s\n", mode))
  cat("\n")

  # Generate synthetic data
  n_obs <- 10000
  n_features <- 200

  cat("Generating synthetic dataset...\n")
  X <- matrix(rnorm(n_obs * n_features), nrow = n_obs, ncol = n_features)
  y <- rnorm(n_obs)

  # Generate hyperparameter grid
  param_grid <- expand.grid(
    alpha = seq(0.1, 1.0, length.out = 10),
    lambda = 10^seq(-3, 2, length.out = 10),
    n_folds = 10
  )
  param_grid <- param_grid[1:n_params, ]

  if (mode == "local-seq") {
    plan(sequential)
  } else if (mode == "local-par") {
    n_cores <- get_performance_cores()
    cat(sprintf("Using %d performance cores\n", n_cores))
    plan(multisession, workers = n_cores)
  } else if (mode == "ec2") {
    plan(starburst,
         workers = 200,
         launch_type = "EC2",
         instance_type = "c7g.xlarge")
  }

  cat("Running hyperparameter search...\n")
  start_time <- Sys.time()

  results <- future_lapply(1:nrow(param_grid),
                           function(i) {
                             train_model_with_params(i, X, y, param_grid[i, ])
                           },
                           future.seed = TRUE)

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  # Find best parameters
  cv_errors <- sapply(results, function(x) x$cv_error)
  best_idx <- which.min(cv_errors)
  best_params <- results[[best_idx]]

  cat("\n=== RESULTS ===\n")
  cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n",
              elapsed, elapsed / 60))
  cat(sprintf("Parameter combinations tested: %d\n", n_params))
  cat(sprintf("Best CV error: %.4f\n", best_params$cv_error))
  cat(sprintf("Best alpha: %.3f, lambda: %.4f\n",
              best_params$alpha, best_params$lambda))
  cat("\n")

  invisible(results)
}

# ============================================================================
# Main execution
# ============================================================================

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    cat("Usage: Rscript benchmark-heavy.R <benchmark> <mode>\n")
    cat("\nBenchmarks:\n")
    cat("  mcmc        - Bayesian MCMC chains\n")
    cat("  bootstrap   - Bootstrap resampling with GLM\n")
    cat("  hyperparam  - Hyperparameter grid search\n")
    cat("  all         - Run all benchmarks\n")
    cat("\nModes:\n")
    cat("  local-seq   - Sequential execution\n")
    cat("  local-par   - Local parallel (performance cores)\n")
    cat("  ec2         - AWS ECS on EC2\n")
    quit(status = 1)
  }

  benchmark <- args[1]
  mode <- if (length(args) > 1) args[2] else "local-par"

  cat("\n")
  cat("====================================================================== \n")
  cat(sprintf("HEAVY COMPUTATIONAL BENCHMARKS\n"))
  cat("====================================================================== \n")
  cat(sprintf("Hostname: %s\n", Sys.info()["nodename"]))
  cat(sprintf("Platform: %s %s\n", Sys.info()["machine"], Sys.info()["sysname"]))
  cat(sprintf("R version: %s\n", R.version.string))

  if (benchmark == "mcmc" || benchmark == "all") {
    benchmark_mcmc(n_chains = 100, mode = mode)
  }

  if (benchmark == "bootstrap" || benchmark == "all") {
    benchmark_bootstrap(n_bootstrap = 500, mode = mode)
  }

  if (benchmark == "hyperparam" || benchmark == "all") {
    benchmark_hyperparameter_search(n_params = 200, mode = mode)
  }
}

if (!interactive()) {
  main()
}
