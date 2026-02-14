#!/usr/bin/env Rscript
# Inspect what's in the plan

Sys.setenv(AWS_PROFILE = "aws")
library(starburst)
library(future)

cat("Setting up EC2 plan...\n")

plan(starburst,
     workers = 2,
     cpu = 2,
     memory = "4GB",
     launch_type = "EC2",
     instance_type = "c6a.large"
)

cat("\nInspecting plan...\n")
current_plan <- plan("list")

cat("Number of strategies:", length(current_plan), "\n")

for (i in seq_along(current_plan)) {
  cat(sprintf("\n Strategy %d:\n", i))
  strategy <- current_plan[[i]]
  cat("  Class:", class(strategy), "\n")
  cat("  Mode:", mode(strategy), "\n")
  cat("  Attributes:", paste(names(attributes(strategy)), collapse = ", "), "\n")

  # Check if it has the backend attribute
  backend <- attr(strategy, "backend")
  if (!is.null(backend)) {
    cat("  Backend found!\n")
    cat("    Backend class:", class(backend), "\n")
    cat("    Backend is environment:", is.environment(backend), "\n")
  } else {
    cat("  No backend attribute\n")
  }
}

# Also check options
cat("\n\nChecking options...\n")
backend_opt <- getOption("starburst.current_backend")
if (!is.null(backend_opt)) {
  cat("Backend in options:\n")
  cat("  Class:", class(backend_opt), "\n")
  cat("  Is environment:", is.environment(backend_opt), "\n")
  cat("  Has StarburstBackend class:", inherits(backend_opt, "StarburstBackend"), "\n")
} else {
  cat("No backend in options\n")
}
