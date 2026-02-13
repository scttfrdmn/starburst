#!/usr/bin/env Rscript

# Install goodpractice if needed
if (!requireNamespace("goodpractice", quietly = TRUE)) {
  install.packages("goodpractice", repos = "https://cloud.r-project.org")
}

library(goodpractice)

cat("Running goodpractice analysis...\n")
cat("This may take a few minutes...\n\n")

# Run comprehensive checks
gp_result <- gp(checks = all_checks())

# Print results
print(gp_result)

# Show failures
cat("\n=== Issues Found ===\n")
failed_checks <- results(gp_result)
if (length(failed_checks) > 0) {
  for (check in failed_checks) {
    cat(sprintf("\n%s:\n", check$check))
    if (length(check$positions) > 0) {
      for (pos in head(check$positions, 10)) {
        cat(sprintf("  %s:%d: %s\n", pos$filename, pos$line_number, pos$message))
      }
    }
  }
} else {
  cat("No issues found!\n")
}
