devtools::load_all()
library(future)

cat("Setting up plan...\n")
plan(starburst, workers=2, cpu=1, memory="2GB")

cat("\nChecking backend storage:\n")
backend <- getOption("starburst.current_backend")
cat("Backend exists in options:", !is.null(backend), "\n")

if (!is.null(backend)) {
  cat("Backend class:", class(backend), "\n")
  cat("Cluster ID:", getOption("starburst.current_cluster_id"), "\n")
}

cat("\nTrying to create a future:\n")
f <- try(starburst:::future.starburst(1+1))
if (inherits(f, "try-error")) {
  cat("Error creating future\n")
  print(f)
} else {
  cat("Success! Future class:", class(f), "\n")
  cat("Task ID:", f$task_id, "\n")
}
