#!/usr/bin/env Rscript
# Debug what's in the future object

Sys.setenv(AWS_PROFILE = "aws")
library(starburst)
library(future)

cat("Setting up EC2 plan...\n")
plan(starburst, workers=2, launch_type='EC2', instance_type='c6a.large')

cat("\nCreating future...\n")

# Monkey-patch resolved to inspect the future
original_resolved <- resolved.StarburstFuture
resolved.StarburstFuture <- function(future, ...) {
  cat("\n=== Future Object Structure ===\n")
  cat("Class:", class(future), "\n")
  cat("Names:", paste(names(future), collapse=", "), "\n")
  cat("\nFields:\n")
  for (name in names(future)) {
    val <- future[[name]]
    cat(sprintf("  %s: %s\n", name, class(val)[1]))
  }

  # Call original
  original_resolved(future, ...)
}

f <- future({
  Sys.info()[["nodename"]]
})

cat("\nFuture created, checking if resolved...\n")
is_resolved <- resolved(f)
cat("Resolved:", is_resolved, "\n")
