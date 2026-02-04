#!/usr/bin/env Rscript
# Test the simplified starburst_map API

library(starburst)

cat("Testing starburst_map API\n")
cat("========================\n\n")

# Test with simple local computation (without AWS for now)
cat("Testing with small dataset (4 items, 2 workers)...\n\n")

# Simple square function
result <- starburst_map(
  1:4,
  function(x) x^2,
  workers = 2,
  .progress = TRUE
)

cat("\nResults:\n")
print(result)

cat("\nExpected: 1, 4, 9, 16\n")
cat(sprintf("Actual: %s\n", paste(unlist(result), collapse = ", ")))

if (all(unlist(result) == c(1, 4, 9, 16))) {
  cat("\n✓ Test passed!\n")
} else {
  cat("\n✗ Test failed\n")
  quit(status = 1)
}
