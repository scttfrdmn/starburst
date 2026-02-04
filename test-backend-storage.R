devtools::load_all()
library(future)

cat("Setting up plan...\n")
plan(starburst, workers=2, cpu=1, memory="2GB")

cat("\nChecking backend storage:\n")
state_env <- get0(".starburst_state", envir = asNamespace("starburst"))
cat("State env exists:", !is.null(state_env), "\n")

if (!is.null(state_env)) {
  cat("Backend exists in state:", !is.null(state_env$backend), "\n")
  if (!is.null(state_env$backend)) {
    cat("Backend class:", class(state_env$backend), "\n")
    cat("Cluster ID:", state_env$cluster_id, "\n")
  }
} else {
  cat("State env is NULL - this is the problem!\n")
}

cat("\nTrying to create a future:\n")
f <- try(starburst:::future.starburst(1+1))
if (inherits(f, "try-error")) {
  cat("Error creating future\n")
} else {
  cat("Success! Future class:", class(f), "\n")
  cat("Task ID:", f$task_id, "\n")
}
