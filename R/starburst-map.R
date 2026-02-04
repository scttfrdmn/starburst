#' Map Function Over Data Using AWS Fargate
#'
#' Parallel map function that executes on AWS Fargate using the Future backend
#'
#' @param .x A vector or list to iterate over
#' @param .f A function to apply to each element
#' @param workers Number of parallel workers (default: 10)
#' @param cpu CPU units per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (e.g., "8GB")
#' @param region AWS region
#' @param timeout Maximum runtime in seconds per task
#' @param .progress Show progress bar (default: TRUE)
#' @param ... Additional arguments passed to .f
#'
#' @return A list of results, one per element of .x
#' @export
#'
#' @examples
#' \dontrun{
#' # Simple parallel computation
#' results <- starburst_map(1:100, function(x) x^2, workers = 10)
#'
#' # With custom configuration
#' results <- starburst_map(
#'   data_list,
#'   expensive_function,
#'   workers = 50,
#'   cpu = 4,
#'   memory = "8GB"
#' )
#' }
starburst_map <- function(.x, .f, workers = 10, cpu = 4, memory = "8GB",
                          region = NULL, timeout = 3600, .progress = TRUE, ...) {

  # Validate inputs
  validate_workers(workers)
  validate_cpu(cpu)
  validate_memory(memory)

  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"

  # Setup progress reporting
  if (.progress) {
    cat_info(sprintf("🚀 Starting starburst cluster with %d workers\n", workers))
  }

  start_time <- Sys.time()

  # Set up the Future plan
  old_plan <- future::plan()
  on.exit({
    future::plan(old_plan)
  }, add = TRUE)

  future::plan(
    starburst,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout
  )

  # Execute using furrr
  tryCatch({
    # Pass extra arguments via purrr-style partial function
    if (length(list(...)) > 0) {
      extra_args <- list(...)
      .f_wrapped <- function(x) {
        do.call(.f, c(list(x), extra_args))
      }
    } else {
      .f_wrapped <- .f
    }

    results <- furrr::future_map(
      .x,
      .f_wrapped,
      .options = furrr::furrr_options(
        seed = TRUE,
        scheduling = 1.0  # Send all tasks immediately
      )
    )

    if (.progress) {
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      cat_success(sprintf("\n✓ Completed in %.1f seconds\n", elapsed))

      # Get backend for cost estimate
      evaluator <- future::plan("next")
      backend <- attr(evaluator, "backend")
      if (!is.null(backend)) {
        cost_est <- estimate_cost(workers, cpu, memory)
        hours <- elapsed / 3600
        actual_cost <- cost_est$per_hour * hours
        cat_info(sprintf("💰 Estimated cost: $%.2f\n", actual_cost))
      }
    }

    results
  }, error = function(e) {
    stop(sprintf("starburst_map failed: %s", e$message))
  })
}

#' Create a Starburst Cluster
#'
#' Creates a cluster object for managing AWS Fargate workers using Future backend
#'
#' @param workers Number of parallel workers
#' @param cpu CPU units per worker
#' @param memory Memory per worker
#' @param region AWS region
#' @param timeout Maximum runtime in seconds
#'
#' @return A starburst_cluster object
#' @export
#'
#' @examples
#' \dontrun{
#' cluster <- starburst_cluster(workers = 20)
#' results <- cluster$map(data, function(x) x * 2)
#' }
starburst_cluster <- function(workers = 10, cpu = 4, memory = "8GB",
                              region = NULL, timeout = 3600) {

  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"

  # Setup the Future plan (this does quota checking internally)
  evaluator <- future::plan(
    starburst,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout
  )

  # Get backend from evaluator
  backend <- attr(evaluator, "backend")

  # Create cluster object
  cluster <- list(
    evaluator = evaluator,
    backend = backend,
    cluster_id = backend$cluster_id,
    workers = backend$workers,
    cpu = backend$cpu,
    memory = backend$memory,
    region = backend$region,
    created_at = backend$created_at
  )

  # Add methods
  cluster$map <- function(.x, .f, .progress = TRUE) {
    starburst_cluster_map(cluster, .x, .f, .progress)
  }

  cluster$estimate_cost <- function(elapsed_seconds) {
    cost_est <- estimate_cost(cluster$workers, cluster$cpu, cluster$memory)
    hours <- elapsed_seconds / 3600
    cost_est$per_hour * hours
  }

  cluster$shutdown <- function() {
    cleanup_cluster(cluster$backend)
    future::plan(future::sequential)
  }

  class(cluster) <- "starburst_cluster"

  cluster
}

#' Execute Map on Starburst Cluster
#'
#' Internal function to execute parallel map using Future backend
#'
#' @keywords internal
starburst_cluster_map <- function(cluster, .x, .f, .progress = TRUE) {

  n <- length(.x)

  if (.progress) {
    cat_info(sprintf("📊 Processing %d items with %d workers\n", n, cluster$workers))
  }

  start_time <- Sys.time()

  # Execute using furrr with the cluster's Future plan
  results <- furrr::future_map(
    .x,
    .f,
    .options = furrr::furrr_options(
      seed = TRUE,
      scheduling = 1.0  # Send all tasks immediately
    )
  )

  if (.progress) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat_success(sprintf("✓ Completed %d items in %.1f seconds\n", n, elapsed))
  }

  results
}

#' Null-coalescing operator
#' @keywords internal
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
