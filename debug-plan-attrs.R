#!/usr/bin/env Rscript
# Check if backend attribute is actually accessible

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

cat("\nChecking backend attribute directly...\n")
current_plan <- plan("list")
strategy <- current_plan[[1]]

cat("All attributes:", paste(names(attributes(strategy)), collapse = ", "), "\n\n")

# Try to access backend directly
backend_attr <- attr(strategy, "backend", exact = TRUE)
cat("Backend attribute (exact=TRUE):", if(is.null(backend_attr)) "NULL" else "EXISTS", "\n")

if (!is.null(backend_attr)) {
  cat("  Class:", class(backend_attr), "\n")
  cat("  Is environment:", is.environment(backend_attr), "\n")
}

# Check options
backend_opt <- getOption("starburst.current_backend")
cat("\nBackend in options:", if(is.null(backend_opt)) "NULL" else "EXISTS", "\n")

if (!is.null(backend_opt)) {
  cat("  Class:", class(backend_opt), "\n")
  cat("  Is environment:", is.environment(backend_opt), "\n")
}

# Try to print all attributes including hidden ones
cat("\nAll attributes (including hidden):\n")
all_attrs <- attributes(strategy)
for (name in names(all_attrs)) {
  cat(sprintf("  %s: %s\n", name, class(all_attrs[[name]])[1]))
}
