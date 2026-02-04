#!/usr/bin/env Rscript
# End-to-end AWS test with dev version

devtools::load_all(".")

cat("\n")
cat("═══════════════════════════════════════\n")
cat("  staRburst E2E Test (Dev Version)\n")
cat("═══════════════════════════════════════\n")
cat("\n")

# Test with small dataset
cat("Testing: 4 items, 2 workers\n")
cat("Function: x^2\n\n")

start_time <- Sys.time()

result <- tryCatch({
  starburst_map(
    1:4,
    function(x) {
      Sys.sleep(2)  # Simulate some work
      x^2
    },
    workers = 2,
    .progress = TRUE
  )
}, error = function(e) {
  cat("\n❌ Error:\n")
  cat(e$message, "\n")
  cat("\nCall stack:\n")
  print(sys.calls())
  NULL
})

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n")
cat("═══════════════════════════════════════\n")

if (!is.null(result)) {
  cat("✓ TEST PASSED\n\n")

  cat("Results:\n")
  cat(sprintf("  Expected: %s\n", paste(c(1, 4, 9, 16), collapse = ", ")))
  cat(sprintf("  Got:      %s\n", paste(unlist(result), collapse = ", ")))

  cat(sprintf("\nTotal time: %.1f seconds\n", elapsed))

  if (all(unlist(result) == c(1, 4, 9, 16))) {
    cat("\n🎉 SUCCESS! staRburst is working on AWS!\n")
  } else {
    cat("\n⚠️  WARNING: Results don't match expected values\n")
  }
} else {
  cat("❌ TEST FAILED\n")
  cat(sprintf("Total time: %.1f seconds\n", elapsed))
}

cat("═══════════════════════════════════════\n")
cat("\n")
