#!/usr/bin/env Rscript
# Benchmark Runner: Collects performance data for local vs starburst
#
# This script should be run:
# 1. On orion.local (for local parallel baseline)
# 2. From your Mac (for starburst EC2 comparison)
#
# Results are saved to benchmark-results-{mode}-{timestamp}.rds

suppressPackageStartupMessages({
  library(future)
  library(future.apply)
})

# Detect performance cores on Mac (Apple Silicon)
get_performance_cores <- function() {
  if (Sys.info()["sysname"] == "Darwin") {
    # Try to get performance cores (Apple Silicon)
    p_cores <- suppressWarnings(
      system("sysctl -n hw.perflevel0.logicalcpu 2>/dev/null", intern = TRUE)
    )

    if (length(p_cores) > 0 && !is.na(as.integer(p_cores))) {
      return(as.integer(p_cores))
    }
  }

  # Fallback to all cores - 1
  return(parallel::detectCores() - 1)
}

# Monte Carlo simulation (from examples)
simulate_portfolio <- function(seed, initial_value = 100000,
                               mean_return = 0.0003, sd_return = 0.02) {
  set.seed(seed)

  # 252 trading days
  daily_returns <- rnorm(252, mean = mean_return, sd = sd_return)
  daily_values <- initial_value * cumprod(1 + daily_returns)

  final_value <- daily_values[252]
  total_return <- (final_value - initial_value) / initial_value

  running_max <- cummax(daily_values)
  drawdowns <- (daily_values - running_max) / running_max
  max_drawdown <- min(drawdowns)

  sharpe_ratio <- mean(daily_returns) / sd(daily_returns) * sqrt(252)

  list(
    final_value = final_value,
    total_return = total_return,
    max_drawdown = max_drawdown,
    sharpe_ratio = sharpe_ratio
  )
}

# Run benchmark
run_benchmark <- function(mode, n_simulations = 1000, workers = NULL,
                         instance_type = NULL, use_spot = FALSE) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat(sprintf("BENCHMARK: %s\n", toupper(mode)))
  cat(strrep("=", 70), "\n")

  system_info <- list(
    hostname = Sys.info()[["nodename"]],
    os = Sys.info()[["sysname"]],
    release = Sys.info()[["release"]],
    machine = Sys.info()[["machine"]],
    r_version = R.version.string
  )

  cat(sprintf("Hostname: %s\n", system_info$hostname))
  cat(sprintf("Platform: %s %s\n", system_info$machine, system_info$os))
  cat(sprintf("R version: %s\n", system_info$r_version))
  cat(sprintf("Simulations: %d\n", n_simulations))

  if (mode == "local-sequential") {
    cat("Mode: Sequential (1 core)\n\n")
    plan(sequential)
    workers <- 1

  } else if (mode == "local-parallel") {
    if (is.null(workers)) workers <- get_performance_cores()
    cat(sprintf("Mode: Parallel (%d cores - performance only)\n\n", workers))
    plan(multisession, workers = workers)

  } else if (mode == "starburst-ec2") {
    if (!requireNamespace("starburst", quietly = TRUE)) {
      cat("ERROR: starburst package not available\n")
      return(NULL)
    }

    devtools::load_all("/Users/scttfrdmn/src/starburst", quiet = TRUE)

    if (is.null(workers)) workers <- 25
    if (is.null(instance_type)) instance_type <- "c6a.large"

    cat(sprintf("Mode: staRburst EC2 (%d workers on %s%s)\n",
                workers, instance_type, if(use_spot) " SPOT" else ""))
    cat(sprintf("Architecture: %s\n\n",
                get_architecture_from_instance_type(instance_type)))

    plan(starburst,
         workers = workers,
         cpu = 2,
         memory = "4GB",
         launch_type = "EC2",
         instance_type = instance_type,
         use_spot = use_spot,
         warm_pool_timeout = 600,
         region = "us-east-1"
    )

  } else {
    cat("ERROR: Unknown mode:", mode, "\n")
    return(NULL)
  }

  # Run benchmark
  cat("Running benchmark...\n")
  start_time <- Sys.time()

  results <- future_lapply(1:n_simulations, simulate_portfolio)

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  plan(sequential)  # Clean up

  # Analyze results
  final_values <- sapply(results, function(x) x$final_value)
  total_returns <- sapply(results, function(x) x$total_return)
  sharpe_ratios <- sapply(results, function(x) x$sharpe_ratio)

  # Compute summary stats
  summary_stats <- list(
    mean_final_value = mean(final_values),
    median_final_value = median(final_values),
    sd_final_value = sd(final_values),
    mean_return = mean(total_returns),
    mean_sharpe = mean(sharpe_ratios),
    prob_loss = sum(final_values < 100000) / n_simulations
  )

  # Print results
  cat("\n")
  cat("=== RESULTS ===\n")
  cat(sprintf("Execution time: %.2f seconds (%.2f minutes)\n",
              elapsed, elapsed/60))
  cat(sprintf("Workers: %d\n", workers))
  cat(sprintf("Throughput: %.1f simulations/second\n",
              n_simulations / elapsed))
  cat(sprintf("\nMean final value: $%s\n",
              format(round(summary_stats$mean_final_value), big.mark = ",")))
  cat(sprintf("Mean return: %.2f%%\n", summary_stats$mean_return * 100))
  cat(sprintf("Probability of loss: %.1f%%\n",
              summary_stats$prob_loss * 100))

  # Save results
  timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  output_file <- sprintf("benchmark-results-%s-%s.rds", mode, timestamp)

  benchmark_data <- list(
    mode = mode,
    timestamp = Sys.time(),
    system_info = system_info,
    config = list(
      n_simulations = n_simulations,
      workers = workers,
      instance_type = instance_type,
      use_spot = use_spot
    ),
    performance = list(
      elapsed_seconds = elapsed,
      throughput = n_simulations / elapsed,
      workers = workers
    ),
    results_summary = summary_stats,
    raw_results = results
  )

  saveRDS(benchmark_data, output_file)
  cat(sprintf("\n✓ Results saved to: %s\n", output_file))

  invisible(benchmark_data)
}

# Load and compare benchmarks
compare_benchmarks <- function(file_pattern = "benchmark-results-*.rds") {
  files <- list.files(pattern = file_pattern)

  if (length(files) == 0) {
    cat("No benchmark files found matching:", file_pattern, "\n")
    return(invisible(NULL))
  }

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("BENCHMARK COMPARISON\n")
  cat(strrep("=", 80), "\n\n")

  benchmarks <- lapply(files, readRDS)
  names(benchmarks) <- sapply(benchmarks, function(b) b$mode)

  # Print comparison table
  cat(sprintf("%-25s %10s %12s %15s %12s\n",
              "Mode", "Workers", "Time (sec)", "Throughput", "Speedup"))
  cat(strrep("-", 80), "\n")

  baseline <- benchmarks[[1]]$performance$elapsed_seconds

  for (b in benchmarks) {
    speedup <- baseline / b$performance$elapsed_seconds

    cat(sprintf("%-25s %10d %12.1f %15.1f %12.1fx\n",
                b$mode,
                b$performance$workers,
                b$performance$elapsed_seconds,
                b$performance$throughput,
                speedup))
  }

  cat(strrep("=", 80), "\n\n")

  # Cost comparison (if EC2)
  ec2_benchmarks <- benchmarks[grep("ec2", names(benchmarks))]

  if (length(ec2_benchmarks) > 0) {
    cat("COST ESTIMATES (EC2 runs only):\n")
    cat(strrep("-", 80), "\n")

    devtools::load_all("/Users/scttfrdmn/src/starburst", quiet = TRUE)

    for (name in names(ec2_benchmarks)) {
      b <- ec2_benchmarks[[name]]

      cost <- estimate_cost(
        workers = b$config$workers,
        cpu = 2,
        memory = "4GB",
        estimated_runtime_hours = b$performance$elapsed_seconds / 3600,
        launch_type = "EC2",
        instance_type = b$config$instance_type,
        use_spot = b$config$use_spot
      )

      cat(sprintf("%-25s: $%.4f (%.1f minutes @ $%.2f/hr)\n",
                  name,
                  cost$total_estimated,
                  b$performance$elapsed_seconds / 60,
                  cost$per_instance * cost$instances_needed))
    }

    cat("\n")
  }

  invisible(benchmarks)
}

# Main
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    cat("\nUsage: Rscript benchmark-runner.R [mode] [options]\n\n")
    cat("Modes:\n")
    cat("  local-seq        - Local sequential (baseline)\n")
    cat("  local-par        - Local parallel (all cores)\n")
    cat("  ec2              - staRburst EC2 (25 workers, c6a.large)\n")
    cat("  ec2-arm64        - staRburst EC2 ARM64 (25 workers, c7g.xlarge)\n")
    cat("  ec2-spot         - staRburst EC2 Spot (25 workers, c6a.large)\n")
    cat("  compare          - Compare all saved benchmarks\n\n")
    cat("Examples:\n")
    cat("  Rscript benchmark-runner.R local-seq\n")
    cat("  Rscript benchmark-runner.R ec2\n")
    cat("  Rscript benchmark-runner.R compare\n\n")
    return(invisible(NULL))
  }

  mode <- tolower(args[1])
  n_simulations <- 1000  # Standard benchmark size

  if (mode == "compare") {
    compare_benchmarks()
  } else if (mode == "local-seq") {
    run_benchmark("local-sequential", n_simulations = n_simulations)
  } else if (mode == "local-par") {
    run_benchmark("local-parallel", n_simulations = n_simulations)
  } else if (mode == "ec2") {
    run_benchmark("starburst-ec2", n_simulations = n_simulations,
                  workers = 25, instance_type = "c6a.large")
  } else if (mode == "ec2-arm64") {
    run_benchmark("starburst-ec2", n_simulations = n_simulations,
                  workers = 25, instance_type = "c7g.xlarge")
  } else if (mode == "ec2-spot") {
    run_benchmark("starburst-ec2", n_simulations = n_simulations,
                  workers = 25, instance_type = "c6a.large", use_spot = TRUE)
  } else {
    cat("Unknown mode:", mode, "\n")
    cat("Run with no arguments for usage\n")
  }
}

if (!interactive()) {
  main()
}
