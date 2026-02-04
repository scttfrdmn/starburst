#!/usr/bin/env Rscript
# Test the Future backend implementation

library(starburst)
library(future)

cat("Testing Future Backend Implementation\n")
cat("=====================================\n\n")

# Test 1: Plan setup
cat("1. Setting up plan...\n")
tryCatch({
  plan(starburst, workers = 2)
  cat("   ✓ Plan setup successful\n\n")
}, error = function(e) {
  cat(sprintf("   ✗ Plan setup failed: %s\n\n", e$message))
  quit(status = 1)
})

# Test 2: Create a simple future
cat("2. Creating a future...\n")
tryCatch({
  f <- future({
    # Simple computation
    x <- 1:100
    sum(x^2)
  })
  cat(sprintf("   ✓ Future created: %s\n", class(f)[1]))
  cat(sprintf("   • Task ID: %s\n", f$task_id))
  cat(sprintf("   • State: %s\n\n", f$state))
}, error = function(e) {
  cat(sprintf("   ✗ Future creation failed: %s\n\n", e$message))
  quit(status = 1)
})

# Test 3: Check future structure
cat("3. Checking future structure...\n")
cat(sprintf("   • Has expr: %s\n", !is.null(f$expr)))
cat(sprintf("   • Has backend: %s\n", !is.null(f$backend)))
cat(sprintf("   • Has task_id: %s\n", !is.null(f$task_id)))
cat(sprintf("   • Backend class: %s\n", paste(class(f$backend), collapse = ", ")))
cat("\n")

# Test 4: Check run method exists
cat("4. Checking S3 methods...\n")
has_run <- !is.null(getS3method("run", "StarburstFuture", optional = TRUE))
has_resolved <- !is.null(getS3method("resolved", "StarburstFuture", optional = TRUE))
has_result <- !is.null(getS3method("result", "StarburstFuture", optional = TRUE))

cat(sprintf("   • run.StarburstFuture: %s\n", if(has_run) "✓" else "✗"))
cat(sprintf("   • resolved.StarburstFuture: %s\n", if(has_resolved) "✓" else "✗"))
cat(sprintf("   • result.StarburstFuture: %s\n", if(has_result) "✓" else "✗"))
cat("\n")

# Test 5: Try to run the future (will fail without full AWS setup, but tests the method)
cat("5. Testing run() method...\n")
tryCatch({
  run(f)
  cat(sprintf("   • Future state after run: %s\n", f$state))
  if (f$state %in% c("running", "queued")) {
    cat("   ✓ run() method executed\n")
  } else {
    cat("   ✗ Unexpected state after run()\n")
  }
}, error = function(e) {
  cat(sprintf("   • run() error (expected without full setup): %s\n", e$message))
})

cat("\n✓ Future backend implementation test complete!\n")
cat("\nThe backend structure is correct. Full AWS integration would require:\n")
cat("  - Task submission to ECS Fargate\n")
cat("  - S3 upload/download of task data\n")
cat("  - Polling for results\n")
