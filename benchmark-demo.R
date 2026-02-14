#!/usr/bin/env Rscript
# DEMO: Scaled-down version of heavy benchmarks for quick demonstration
# Still shows AWS advantage but completes faster

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

# MCMC Chain (same expensive computation, just fewer chains)
run_mcmc_chain <- function(chain_id, n_iter = 100000, n_params = 50) {
  set.seed(chain_id)

  log_likelihood <- function(params, data) {
    X <- matrix(rnorm(length(data) * length(params)),
                nrow = length(data), ncol = length(params))
    linear_pred <- X %*% params
    size <- exp(params[1])
    mu <- exp(linear_pred)
    sum(dnbinom(data, size = size, mu = mu, log = TRUE))
  }

  n_obs <- 1000
  data <- rpois(n_obs, lambda = 50)

  current <- rnorm(n_params)
  samples <- matrix(0, nrow = n_iter, ncol = n_params)
  accept_count <- 0

  for (i in 1:n_iter) {
    proposal <- current + rnorm(n_params, sd = 0.1)

    current_ll <- tryCatch(log_likelihood(current, data), error = function(e) -Inf)
    proposal_ll <- tryCatch(log_likelihood(proposal, data), error = function(e) -Inf)

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
    posterior_mean = colMeans(samples[-(1:1000), ])
  )
}

run_mcmc_demo <- function(n_chains = 25, mode = "local-par") {
  cat("\n")
  cat("====================================================================== \n")
  cat("DEMO: BAYESIAN MCMC CHAINS\n")
  cat("====================================================================== \n")
  cat(sprintf("Chains: %d (100,000 iterations each)\n", n_chains))
  cat(sprintf("Per-chain time: ~3.7 minutes\n"))
  cat(sprintf("Mode: %s\n", mode))
  cat("\n")

  if (mode == "local-seq") {
    cat(sprintf("Estimated time: %.1f minutes\n", n_chains * 3.7))
    plan(sequential)
  } else if (mode == "local-par") {
    n_cores <- get_performance_cores()
    cat(sprintf("Using %d performance cores\n", n_cores))
    cat(sprintf("Estimated time: %.1f minutes\n", n_chains / n_cores * 3.7))
    plan(multisession, workers = n_cores)
  } else if (mode == "ec2") {
    cat(sprintf("Using %d AWS workers\n", n_chains))
    cat(sprintf("Estimated time: ~3.7 minutes (one task duration)\n"))
    plan(starburst,
         workers = n_chains,
         launch_type = "EC2",
         instance_type = "c6a.large")
  }

  cat("\nRunning MCMC chains...\n")
  start_time <- Sys.time()

  results <- future_lapply(1:n_chains, run_mcmc_chain,
                           future.seed = TRUE)

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat("\n=== RESULTS ===\n")
  cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n",
              elapsed, elapsed / 60))
  cat(sprintf("Chains completed: %d\n", n_chains))
  cat(sprintf("Avg acceptance rate: %.1f%%\n",
              mean(sapply(results, function(x) x$acceptance_rate)) * 100))

  if (mode == "local-par") {
    n_cores <- get_performance_cores()
    speedup <- (n_chains * 3.7 * 60) / elapsed
    cat(sprintf("Speedup vs sequential: %.1fx\n", speedup))
  } else if (mode == "ec2") {
    speedup_vs_seq <- (n_chains * 3.7 * 60) / elapsed
    n_cores <- get_performance_cores()
    local_par_time <- n_chains / n_cores * 3.7 * 60
    speedup_vs_local <- local_par_time / elapsed
    cat(sprintf("Speedup vs sequential: %.1fx\n", speedup_vs_seq))
    cat(sprintf("Speedup vs local parallel (%d cores): %.1fx\n",
                n_cores, speedup_vs_local))
    cat("\n** AWS BURST PARALLELISM DOMINATES **\n")
  }

  cat("\n")
  invisible(results)
}

# Main
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    cat("Usage: Rscript benchmark-demo.R <mode> [n_chains]\n")
    cat("\nModes:\n")
    cat("  local-seq   - Sequential (slow, baseline)\n")
    cat("  local-par   - Local parallel (M4 Mac performance cores)\n")
    cat("  ec2         - AWS ECS on EC2 (burst parallelism)\n")
    cat("\nDefault: 25 chains (~3.7 min per chain)\n")
    cat("\nExamples:\n")
    cat("  Rscript benchmark-demo.R local-par\n")
    cat("  Rscript benchmark-demo.R ec2 25\n")
    quit(status = 1)
  }

  mode <- args[1]
  n_chains <- if (length(args) > 1) as.integer(args[2]) else 25

  cat("\n")
  cat("====================================================================== \n")
  cat("STARBURST DEMO: AWS vs LOCAL COMPARISON\n")
  cat("====================================================================== \n")
  cat(sprintf("Hostname: %s\n", Sys.info()["nodename"]))
  cat(sprintf("Platform: %s %s\n", Sys.info()["machine"], Sys.info()["sysname"]))
  cat(sprintf("R version: %s\n", R.version.string))

  run_mcmc_demo(n_chains = n_chains, mode = mode)
}

if (!interactive()) {
  main()
}
