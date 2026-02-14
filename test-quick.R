#!/usr/bin/env Rscript
# Quick Test: Simple example to verify starburst is working
#
# Usage:
#   # Local test (fast)
#   Rscript test-quick.R local
#
#   # EC2 test (uses 5 workers)
#   Rscript test-quick.R ec2
#
#   # EC2 ARM64 test (Graviton)
#   Rscript test-quick.R ec2-arm64

Sys.setenv(AWS_PROFILE = "aws")
suppressPackageStartupMessages({
  devtools::load_all("/Users/scttfrdmn/src/starburst", quiet = TRUE)
  library(future)
  library(future.apply)
})

cat("\n=== staRburst Quick Test ===\n\n")

# Simple test function
test_function <- function(x) {
  Sys.sleep(1)  # Simulate 1 second of work
  list(
    input = x,
    result = x^2,
    platform = Sys.info()[["machine"]],
    hostname = Sys.info()[["nodename"]],
    timestamp = Sys.time()
  )
}

# Get mode from command line
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) > 0) tolower(args[1]) else "help"

if (mode == "help" || mode == "") {
  cat("Usage: Rscript test-quick.R [mode]\n\n")
  cat("Modes:\n")
  cat("  local       - Sequential execution (baseline)\n")
  cat("  ec2         - EC2 c6a.large (x86_64)\n")
  cat("  ec2-arm64   - EC2 c7g.xlarge (ARM64 Graviton)\n")
  cat("  ec2-spot    - EC2 with spot instances\n\n")
  quit(status = 0)
}

n_tasks <- 10
n_workers <- 5

cat(sprintf("Tasks: %d\n", n_tasks))
cat(sprintf("Mode: %s\n", mode))

if (mode == "local") {
  cat("Workers: 1 (sequential)\n\n")
  plan(sequential)

} else if (mode == "ec2") {
  cat(sprintf("Workers: %d (EC2 c6a.large x86_64)\n\n", n_workers))

  plan(starburst,
       workers = n_workers,
       cpu = 2,
       memory = "4GB",
       launch_type = "EC2",
       instance_type = "c6a.large",
       use_spot = FALSE,
       warm_pool_timeout = 600,
       region = "us-east-1"
  )

} else if (mode == "ec2-arm64") {
  cat(sprintf("Workers: %d (EC2 c7g.xlarge ARM64)\n\n", n_workers))

  plan(starburst,
       workers = n_workers,
       cpu = 2,
       memory = "4GB",
       launch_type = "EC2",
       instance_type = "c7g.xlarge",
       use_spot = FALSE,
       warm_pool_timeout = 600,
       region = "us-east-1"
  )

} else if (mode == "ec2-spot") {
  cat(sprintf("Workers: %d (EC2 c6a.large SPOT)\n\n", n_workers))

  plan(starburst,
       workers = n_workers,
       cpu = 2,
       memory = "4GB",
       launch_type = "EC2",
       instance_type = "c6a.large",
       use_spot = TRUE,
       warm_pool_timeout = 600,
       region = "us-east-1"
  )

} else {
  cat("Unknown mode:", mode, "\n")
  quit(status = 1)
}

# Run test
cat("Running test...\n")
start_time <- Sys.time()

results <- future_lapply(1:n_tasks, test_function)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

# Verify results
cat("\n=== Results ===\n")
cat(sprintf("Execution time: %.1f seconds\n", elapsed))

if (mode != "local") {
  platforms <- unique(sapply(results, function(r) r$platform))
  cat(sprintf("Platforms: %s\n", paste(platforms, collapse = ", ")))

  hostnames <- unique(sapply(results, function(r) r$hostname))
  cat(sprintf("Unique hosts: %d\n", length(hostnames)))
}

# Verify correctness
expected_results <- sapply(1:n_tasks, function(x) x^2)
actual_results <- sapply(results, function(r) r$result)
all_correct <- all(expected_results == actual_results)

cat(sprintf("Results correct: %s\n", if(all_correct) "✓ YES" else "✗ NO"))

if (all_correct) {
  cat("\n✓ Test PASSED\n")
} else {
  cat("\n✗ Test FAILED\n")
  quit(status = 1)
}

plan(sequential)  # Clean up
cat("\n")
