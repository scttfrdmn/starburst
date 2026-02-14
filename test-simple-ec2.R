#!/usr/bin/env Rscript
# Simple EC2 test using starburst_map (high-level API)

Sys.setenv(AWS_PROFILE = "aws")
devtools::load_all("/Users/scttfrdmn/src/starburst", quiet = TRUE)

cat("\n=== Simple EC2 Test ===\n\n")

# Simple test function
test_function <- function(x) {
  Sys.sleep(0.5)  # Simulate work
  list(
    input = x,
    result = x^2,
    platform = Sys.info()[["machine"]],
    hostname = Sys.info()[["nodename"]]
  )
}

cat("Running 10 tasks on 5 EC2 workers (c6a.large)...\n\n")

start_time <- Sys.time()

# Use starburst_map instead of future_lapply
results <- starburst_map(
  .x = 1:10,
  .f = test_function,
  workers = 5,
  cpu = 2,
  memory = "4GB",
  launch_type = "EC2",
  instance_type = "c6a.large",
  use_spot = FALSE,
  warm_pool_timeout = 600,
  region = "us-east-1"
)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n=== Results ===\n")
cat(sprintf("Execution time: %.1f seconds\n", elapsed))

platforms <- unique(sapply(results, function(r) r$platform))
cat(sprintf("Platforms: %s\n", paste(platforms, collapse = ", ")))

hostnames <- unique(sapply(results, function(r) r$hostname))
cat(sprintf("Unique hosts: %d\n", length(hostnames)))

# Verify correctness
expected <- sapply(1:10, function(x) x^2)
actual <- sapply(results, function(r) r$result)
all_correct <- all(expected == actual)

cat(sprintf("Results correct: %s\n", if(all_correct) "✓ YES" else "✗ NO"))

if (all_correct) {
  cat("\n✓ EC2 Test PASSED\n\n")
} else {
  cat("\n✗ EC2 Test FAILED\n\n")
  quit(status = 1)
}
