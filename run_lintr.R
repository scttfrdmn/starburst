#!/usr/bin/env Rscript

# Install lintr if needed
if (!requireNamespace("lintr", quietly = TRUE)) {
  install.packages("lintr", repos = "https://cloud.r-project.org")
}

library(lintr)

# Run lintr on package
cat("Running lintr analysis...\n")
lints <- lint_package()

# Print summary
cat(sprintf("\nTotal lints found: %d\n", length(lints)))

# Show first 50 lints
if (length(lints) > 0) {
  cat("\nFirst 50 issues:\n")
  print(head(lints, 50))
}
