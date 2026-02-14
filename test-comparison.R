#!/usr/bin/env Rscript
# Comprehensive Test: Compare Local, Remote (orion.local), and staRburst execution
#
# This script runs a simple Monte Carlo simulation in three modes:
# 1. LOCAL: Sequential execution on this machine
# 2. REMOTE: Parallel execution on orion.local via SSH
# 3. STARBURST_FARGATE: AWS Fargate workers
# 4. STARBURST_EC2: AWS EC2 workers (new!)
#
# Usage:
#   Rscript test-comparison.R [mode]
#
# Modes:
#   local           - Run locally (sequential)
#   remote          - Run on orion.local (parallel via SSH)
#   fargate         - Run on AWS Fargate
#   ec2             - Run on AWS EC2 (fast cold start)
#   all             - Run all modes and compare
#
# Examples:
#   Rscript test-comparison.R local
#   Rscript test-comparison.R ec2
#   Rscript test-comparison.R all

suppressPackageStartupMessages({
  library(future)
  library(future.apply)
})

# Simulation function (simple but realistic)
simulate_portfolio <- function(seed, initial_value = 100000,
                               mean_return = 0.0003, sd_return = 0.02) {
  set.seed(seed)

  # 252 trading days
  daily_returns <- rnorm(252, mean = mean_return, sd = sd_return)
  daily_values <- initial_value * cumprod(1 + daily_returns)

  final_value <- daily_values[252]
  total_return <- (final_value - initial_value) / initial_value

  # Max drawdown
  running_max <- cummax(daily_values)
  drawdowns <- (daily_values - running_max) / running_max
  max_drawdown <- min(drawdowns)

  # Sharpe ratio
  sharpe_ratio <- mean(daily_returns) / sd(daily_returns) * sqrt(252)

  list(
    final_value = final_value,
    total_return = total_return,
    max_drawdown = max_drawdown,
    sharpe_ratio = sharpe_ratio
  )
}

# Print results summary
print_results <- function(results, elapsed, mode, workers = 1) {
  final_values <- sapply(results, function(x) x$final_value)
  total_returns <- sapply(results, function(x) x$total_return)

  cat("\n")
  cat("===", toupper(mode), "RESULTS ===\n")
  cat(sprintf("Workers: %d\n", workers))
  cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n", elapsed, elapsed/60))
  cat(sprintf("Mean final value: $%s\n", format(round(mean(final_values)), big.mark = ",")))
  cat(sprintf("Mean return: %.2f%%\n", mean(total_returns) * 100))
  cat(sprintf("Probability of loss: %.1f%%\n",
              sum(final_values < 100000) / length(results) * 100))
  cat("\n")

  invisible(list(
    mode = mode,
    workers = workers,
    elapsed = elapsed,
    mean_final_value = mean(final_values),
    mean_return = mean(total_returns)
  ))
}

# Run in LOCAL mode (sequential)
run_local <- function(n_simulations = 1000) {
  cat("\n🔧 Running LOCAL (sequential on this machine)...\n")

  plan(sequential)

  start_time <- Sys.time()
  results <- future_lapply(1:n_simulations, simulate_portfolio)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  print_results(results, elapsed, "local", workers = 1)
}

# Run on REMOTE machine (orion.local) via SSH
run_remote <- function(n_simulations = 1000, workers = 8) {
  cat("\n🌐 Running REMOTE (parallel on orion.local via SSH)...\n")

  # Check if orion.local is accessible
  ssh_test <- system("ssh -o ConnectTimeout=5 orion.local 'echo OK' 2>/dev/null",
                     intern = TRUE, ignore.stderr = TRUE)

  if (length(ssh_test) == 0 || ssh_test != "OK") {
    cat("⚠️  Cannot connect to orion.local via SSH\n")
    cat("   Make sure SSH is configured and orion.local is accessible\n")
    return(invisible(NULL))
  }

  cat(sprintf("✓ Connected to orion.local, using %d workers\n", workers))

  # Use future.batchtools with SSH to orion.local
  # Or use multisession if running this script ON orion.local
  if (Sys.info()["nodename"] == "orion.local") {
    # Already on orion, use local multicore
    plan(multisession, workers = workers)
  } else {
    # TODO: Set up SSH cluster
    # For now, fall back to multisession on local machine
    cat("⚠️  SSH cluster not yet configured, using local multisession\n")
    plan(multisession, workers = workers)
  }

  start_time <- Sys.time()
  results <- future_lapply(1:n_simulations, simulate_portfolio)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  plan(sequential)  # Clean up

  print_results(results, elapsed, "remote", workers = workers)
}

# Run on AWS FARGATE
run_fargate <- function(n_simulations = 1000, workers = 25) {
  cat("\n☁️  Running STARBURST FARGATE (AWS Fargate workers)...\n")

  if (!requireNamespace("starburst", quietly = TRUE)) {
    cat("⚠️  starburst package not available\n")
    return(invisible(NULL))
  }

  library(starburst)

  # Check setup
  if (!is_setup_complete()) {
    cat("⚠️  starburst not configured. Run starburst_setup() first\n")
    return(invisible(NULL))
  }

  cat(sprintf("✓ Using %d Fargate workers\n", workers))

  plan(starburst,
       workers = workers,
       cpu = 2,
       memory = "4GB",
       launch_type = "FARGATE",
       region = "us-east-1"
  )

  start_time <- Sys.time()
  results <- future_lapply(1:n_simulations, simulate_portfolio)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  plan(sequential)  # Clean up

  print_results(results, elapsed, "fargate", workers = workers)
}

# Run on AWS EC2 (NEW!)
run_ec2 <- function(n_simulations = 1000, workers = 25,
                    instance_type = "c6a.large", use_spot = FALSE) {
  cat("\n⚡ Running STARBURST EC2 (AWS EC2 workers - fast cold start!)...\n")

  if (!requireNamespace("starburst", quietly = TRUE)) {
    cat("⚠️  starburst package not available\n")
    return(invisible(NULL))
  }

  library(starburst)

  # Check setup
  if (!is_setup_complete()) {
    cat("⚠️  starburst not configured. Run starburst_setup() first\n")
    return(invisible(NULL))
  }

  cat(sprintf("✓ Using %d EC2 workers (%s%s)\n",
              workers, instance_type, if(use_spot) " SPOT" else ""))

  # Get architecture from instance type
  arch <- get_architecture_from_instance_type(instance_type)
  cat(sprintf("✓ Architecture: %s\n", arch))

  # Estimate cost
  cost <- estimate_cost(
    workers = workers,
    cpu = 2,
    memory = "4GB",
    estimated_runtime_hours = 0.1,  # ~6 minutes
    launch_type = "EC2",
    instance_type = instance_type,
    use_spot = use_spot
  )

  cat(sprintf("💰 Estimated cost: $%.3f for this run\n",
              cost$total_estimated * 0.1))  # Pro-rate for actual runtime

  plan(starburst,
       workers = workers,
       cpu = 2,
       memory = "4GB",
       launch_type = "EC2",
       instance_type = instance_type,
       use_spot = use_spot,
       warm_pool_timeout = 600,  # 10 minutes
       region = "us-east-1"
  )

  start_time <- Sys.time()
  results <- future_lapply(1:n_simulations, simulate_portfolio)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  plan(sequential)  # Clean up

  print_results(results, elapsed, paste0("ec2-", instance_type), workers = workers)
}

# Run EC2 with ARM64 (Graviton)
run_ec2_arm64 <- function(n_simulations = 1000, workers = 25, use_spot = FALSE) {
  cat("\n🚀 Running STARBURST EC2 ARM64 (Graviton3 - best price/performance!)...\n")
  run_ec2(n_simulations, workers, instance_type = "c7g.xlarge", use_spot = use_spot)
}

# Compare all modes
run_all <- function(n_simulations = 1000) {
  cat("\n" %+% "=" %+% strrep("=", 60) %+% "\n")
  cat("COMPREHENSIVE COMPARISON TEST\n")
  cat(strrep("=", 61) %+% "\n")
  cat(sprintf("Running %d simulations in each mode\n", n_simulations))
  cat(strrep("=", 61) %+% "\n")

  results <- list()

  # 1. Local
  results$local <- run_local(n_simulations)

  # 2. Remote (if available)
  results$remote <- run_remote(n_simulations, workers = 8)

  # 3. EC2 x86 (recommended for most workloads)
  results$ec2_x86 <- run_ec2(n_simulations, workers = 25,
                             instance_type = "c6a.large", use_spot = FALSE)

  # 4. EC2 ARM64 (Graviton - best price/performance)
  results$ec2_arm64 <- run_ec2_arm64(n_simulations, workers = 25, use_spot = FALSE)

  # 5. EC2 with SPOT (70% cheaper!)
  results$ec2_spot <- run_ec2(n_simulations, workers = 25,
                              instance_type = "c6a.large", use_spot = TRUE)

  # 6. Fargate (for comparison)
  results$fargate <- run_fargate(n_simulations, workers = 25)

  # Summary comparison
  cat("\n" %+% strrep("=", 61) %+% "\n")
  cat("SUMMARY COMPARISON\n")
  cat(strrep("=", 61) %+% "\n")

  cat(sprintf("%-20s %10s %15s %12s\n", "Mode", "Workers", "Time (sec)", "Speedup"))
  cat(strrep("-", 61) %+% "\n")

  baseline <- if (!is.null(results$local)) results$local$elapsed else NA

  for (name in names(results)) {
    r <- results[[name]]
    if (!is.null(r)) {
      speedup <- if (!is.na(baseline)) baseline / r$elapsed else NA
      cat(sprintf("%-20s %10d %15.1f %12.1fx\n",
                  r$mode, r$workers, r$elapsed, speedup))
    }
  }

  cat(strrep("=", 61) %+% "\n")

  invisible(results)
}

# Main CLI
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  mode <- if (length(args) > 0) tolower(args[1]) else "help"

  n_simulations <- 1000  # Default

  switch(mode,
    "local" = run_local(n_simulations),
    "remote" = run_remote(n_simulations, workers = 8),
    "fargate" = run_fargate(n_simulations, workers = 25),
    "ec2" = run_ec2(n_simulations, workers = 25, instance_type = "c6a.large"),
    "ec2-arm64" = run_ec2_arm64(n_simulations, workers = 25),
    "ec2-spot" = run_ec2(n_simulations, workers = 25,
                         instance_type = "c6a.large", use_spot = TRUE),
    "all" = run_all(n_simulations),
    {
      cat("\nUsage: Rscript test-comparison.R [mode]\n\n")
      cat("Modes:\n")
      cat("  local       - Run locally (sequential)\n")
      cat("  remote      - Run on orion.local (parallel via SSH)\n")
      cat("  fargate     - Run on AWS Fargate\n")
      cat("  ec2         - Run on AWS EC2 (c6a.large)\n")
      cat("  ec2-arm64   - Run on AWS EC2 Graviton (c7g.xlarge)\n")
      cat("  ec2-spot    - Run on AWS EC2 with Spot instances\n")
      cat("  all         - Run all modes and compare\n\n")
      cat("Examples:\n")
      cat("  Rscript test-comparison.R local\n")
      cat("  Rscript test-comparison.R ec2\n")
      cat("  Rscript test-comparison.R all\n\n")
    }
  )
}

# Helper for string concatenation
`%+%` <- function(a, b) paste0(a, b)

# Run if called as script
if (!interactive()) {
  main()
}
