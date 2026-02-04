devtools::load_all()
library(future)

cat("Calling plan.starburst directly...\n")
strategy_result <- starburst:::plan.starburst(
  strategy = starburst,
  workers = 2,
  cpu = 1,
  memory = "2GB"
)

cat("Result class:", class(strategy_result), "\n")

cat("\nChecking backend storage:\n")
backend <- getOption("starburst.current_backend")
cat("Backend exists:", !is.null(backend), "\n")

if (!is.null(backend)) {
  cat("Backend cluster_id:", backend$cluster_id, "\n")

  cat("\nTrying to create a future:\n")
  f <- try(starburst:::future.starburst(1+1))
  if (!inherits(f, "try-error")) {
    cat("Success! Future class:", class(f), "\n")
    cat("Task ID:", f$task_id, "\n")
  }
}
