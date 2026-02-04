#!/usr/bin/env Rscript
# Simple AWS test for starburst_map

devtools::load_all()

cat("================================\n")
cat("Simple AWS Test\n")
cat("================================\n\n")

# Test data
test_data <- 1:4
expected_results <- list(1, 4, 9, 16)

cat("Testing starburst_map() with", length(test_data), "items\n\n")

# Run starburst_map
start_time <- Sys.time()
results <- starburst_map(
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
elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

# Validate
cat("\n--- Results ---\n")
cat("Results:", paste(sapply(results, function(x) x), collapse = ", "), "\n")
cat("Expected:", paste(sapply(expected_results, function(x) x), collapse = ", "), "\n")
cat("Elapsed time:", round(elapsed, 1), "seconds\n\n")

if (identical(results, expected_results)) {
  cat("✅ TEST PASSED\n")
  quit(status = 0)
} else {
  cat("❌ TEST FAILED\n")
  quit(status = 1)
}
