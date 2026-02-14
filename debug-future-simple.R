#!/usr/bin/env Rscript
Sys.setenv(AWS_PROFILE = "aws")
library(starburst)
library(future)

plan(starburst, workers=2, launch_type='EC2', instance_type='c6a.large')

# Create future - this should call launchFuture
f <- tryCatch({
  future({ 42 })
}, error = function(e) {
  cat("Error creating future:", conditionMessage(e), "\n")
  return(NULL)
})

if (!is.null(f)) {
  cat("\n=== Future Created Successfully ===\n")
  cat("Class:", paste(class(f), collapse=", "), "\n")
  cat("Is environment:", is.environment(f), "\n")
  if (is.environment(f)) {
    cat("Names:", paste(names(f), collapse=", "), "\n")
  } else {
    cat("Names:", paste(names(f), collapse=", "), "\n")
  }

  cat("\nTrying to check if resolved (this will test resolved())...\n")
  is_done <- tryCatch({
    resolved(f)
  }, error = function(e) {
    cat("Error in resolved():", conditionMessage(e), "\n")
    traceback()
    return(NA)
  })

  cat("Resolved:", is_done, "\n")
}
