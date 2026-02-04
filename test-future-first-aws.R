#!/usr/bin/env Rscript
# Test Future-first architecture with real AWS

library(starburst)
library(furrr)

cat("===============================================\n")
cat("Testing Future-First Architecture with AWS\n")
cat("===============================================\n\n")

# Test data
test_data <- 1:4
expected_results <- list(1, 4, 9, 16)

# =============================================================================
# TEST 1: Direct Future API with plan()
# =============================================================================
cat("\n=== TEST 1: Direct Future API ===\n")
cat("Testing: plan(future_starburst) + future_map()\n\n")

# Set up plan
old_plan <- future::plan()
future::plan(
  starburst,
  workers = 2,
  cpu = 1,
  memory = "2GB",
  region = "us-east-1"
)

# Execute with furrr
test1_start <- Sys.time()
results1 <- future_map(test_data, function(x) {
  Sys.sleep(2)  # Simulate work
  x^2
})
test1_elapsed <- as.numeric(difftime(Sys.time(), test1_start, units = "secs"))

# Restore plan
future::plan(old_plan)

# Validate
cat("\n--- Test 1 Results ---\n")
cat("Results:", paste(sapply(results1, function(x) x), collapse = ", "), "\n")
cat("Expected:", paste(sapply(expected_results, function(x) x), collapse = ", "), "\n")
cat("Elapsed time:", round(test1_elapsed, 1), "seconds\n")

if (identical(results1, expected_results)) {
  cat("✅ TEST 1 PASSED: Direct Future API works correctly\n")
  test1_pass <- TRUE
} else {
  cat("❌ TEST 1 FAILED: Results don't match expected\n")
  test1_pass <- FALSE
}

# =============================================================================
# TEST 2: starburst_map() wrapper
# =============================================================================
cat("\n=== TEST 2: starburst_map() Wrapper ===\n")
cat("Testing: starburst_map() as Future wrapper\n\n")

test2_start <- Sys.time()
results2 <- starburst_map(
  test_data,
  function(x) {
    Sys.sleep(2)  # Simulate work
    x^2
  },
  workers = 2,
  cpu = 1,
  memory = "2GB",
  .progress = TRUE
)
test2_elapsed <- as.numeric(difftime(Sys.time(), test2_start, units = "secs"))

# Validate
cat("\n--- Test 2 Results ---\n")
cat("Results:", paste(sapply(results2, function(x) x), collapse = ", "), "\n")
cat("Expected:", paste(sapply(expected_results, function(x) x), collapse = ", "), "\n")
cat("Elapsed time:", round(test2_elapsed, 1), "seconds\n")

if (identical(results2, expected_results)) {
  cat("✅ TEST 2 PASSED: starburst_map() wrapper works correctly\n")
  test2_pass <- TRUE
} else {
  cat("❌ TEST 2 FAILED: Results don't match expected\n")
  test2_pass <- FALSE
}

# =============================================================================
# TEST 3: starburst_cluster() wrapper
# =============================================================================
cat("\n=== TEST 3: starburst_cluster() Wrapper ===\n")
cat("Testing: starburst_cluster() + cluster$map()\n\n")

# Create cluster
cluster <- starburst_cluster(
  workers = 2,
  cpu = 1,
  memory = "2GB"
)

# Run first operation
cat("\nOperation 1:\n")
test3a_start <- Sys.time()
results3a <- cluster$map(test_data, function(x) x^2, .progress = TRUE)
test3a_elapsed <- as.numeric(difftime(Sys.time(), test3a_start, units = "secs"))

# Run second operation (reusing cluster)
cat("\nOperation 2:\n")
test3b_start <- Sys.time()
results3b <- cluster$map(test_data, function(x) x * 3, .progress = TRUE)
test3b_elapsed <- as.numeric(difftime(Sys.time(), test3b_start, units = "secs"))

# Shutdown cluster
cluster$shutdown()

# Validate
cat("\n--- Test 3 Results ---\n")
cat("Op 1 Results:", paste(sapply(results3a, function(x) x), collapse = ", "), "\n")
cat("Op 1 Expected:", paste(sapply(expected_results, function(x) x), collapse = ", "), "\n")
cat("Op 1 Elapsed:", round(test3a_elapsed, 1), "seconds\n")

cat("Op 2 Results:", paste(sapply(results3b, function(x) x), collapse = ", "), "\n")
cat("Op 2 Expected:", paste(c(3, 6, 9, 12), collapse = ", "), "\n")
cat("Op 2 Elapsed:", round(test3b_elapsed, 1), "seconds\n")

test3a_pass <- identical(results3a, expected_results)
test3b_pass <- identical(results3b, list(3, 6, 9, 12))

if (test3a_pass && test3b_pass) {
  cat("✅ TEST 3 PASSED: starburst_cluster() wrapper works correctly\n")
  test3_pass <- TRUE
} else {
  cat("❌ TEST 3 FAILED: Results don't match expected\n")
  test3_pass <- FALSE
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================
cat("\n===============================================\n")
cat("FINAL TEST SUMMARY\n")
cat("===============================================\n")
cat("Test 1 (Direct Future API):", ifelse(test1_pass, "✅ PASS", "❌ FAIL"), "\n")
cat("Test 2 (starburst_map):", ifelse(test2_pass, "✅ PASS", "❌ FAIL"), "\n")
cat("Test 3 (starburst_cluster):", ifelse(test3_pass, "✅ PASS", "❌ FAIL"), "\n")
cat("===============================================\n")

all_pass <- test1_pass && test2_pass && test3_pass
if (all_pass) {
  cat("\n🎉 ALL TESTS PASSED - Future-first architecture works!\n\n")
  quit(status = 0)
} else {
  cat("\n❌ SOME TESTS FAILED - See details above\n\n")
  quit(status = 1)
}
