#' Map a Function Over Data on AWS Workers
#'
#' Parallel map function that executes across AWS workers (EC2 by default, or
#' Fargate) using the staRburst Future backend.
#'
#' @param .x A vector or list to iterate over
#' @param .f A function to apply to each element
#' @param workers Number of parallel workers (default: 10)
#' @param cpu CPU units per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (e.g., 8GB)
#' @param region AWS region
#' @param timeout Maximum runtime in seconds per task
#' @param launch_type Compute backend: "EC2" (default) or "FARGATE"
#' @param instance_type EC2 instance type when \code{launch_type = "EC2"}
#'   (default: "c7g.xlarge"). The worker CPU architecture follows the instance
#'   type — Graviton types (e.g. \code{c7g.*}) run ARM64, Intel/AMD types
#'   (e.g. \code{c7i.*}) run x86_64 — so there is no separate platform argument.
#' @param use_spot Use EC2 Spot instances for cost savings (default: TRUE)
#' @param .progress Show progress bar (default: TRUE)
#' @param ... Additional arguments passed to .f
#'
#' @return A list of results, one per element of .x
#' @export
#'
#' @examples
#' \donttest{
#' if (starburst_is_configured()) {
#'   # Simple parallel computation
#'   results <- starburst_map(1:100, function(x) x^2, workers = 10)
#'
#'   # With custom configuration
#'   results <- starburst_map(
#'     data_list,
#'     expensive_function,
#'     workers = 50,
#'     cpu = 4,
#'     memory = "8GB"
#'   )
#'
#'   # Use the Fargate backend instead of the EC2 default
#'   results <- starburst_map(1:100, function(x) x^2,
#'                            workers = 10, launch_type = "FARGATE")
#' }
#' }
starburst_map <- function(.x, .f, workers = 10, cpu = 4, memory = "8GB",
                          region = NULL, timeout = 3600,
                          launch_type = "EC2", instance_type = "c7g.xlarge",
                          use_spot = TRUE, .progress = TRUE, ...) {

  # Validate inputs
  validate_workers(workers)
  validate_cpu(cpu)
  validate_memory(memory)

  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"

  # Setup progress reporting
  if (.progress) {
    cat_info(sprintf("[Starting] Starting starburst cluster with %d workers\n", workers))
  }

  start_time <- Sys.time()

  # Set up the Future plan by calling plan.starburst directly
  # (bypasses Future package dispatch issues)
  old_plan <- future::plan()
  on.exit({
    future::plan(old_plan)
  }, add = TRUE)

  strategy <- plan.starburst(
    strategy = starburst,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout,
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot
  )

  future::plan(strategy)

  # Execute by creating StarburstFuture objects directly
  # Pass extra arguments via wrapper function
  if (length(list(...)) > 0) {
    extra_args <- list(...)
    .f_wrapped <- function(x) {
      do.call(.f, c(list(x), extra_args))
    }
  } else {
    .f_wrapped <- .f
  }

  # Create futures for each item
  n <- length(.x)
  futures <- vector("list", n)

  for (i in seq_along(.x)) {
    item <- .x[[i]]

    # Create globals list with the function and item
    globals_list <- list(
      .f_wrapped = .f_wrapped,
      .item = item
    )

    futures[[i]] <- StarburstFuture(
      expr = quote(.f_wrapped(.item)),
      envir = parent.frame(),
      substitute = FALSE,
      globals = globals_list,  # Pass as globals so they get serialized
      packages = NULL
    )
  }

  # Run all futures
  if (.progress) {
    cat_info(sprintf("[Starting] Submitting %d tasks...\n", n))
  }

  for (future in futures) {
    run(future)
  }

  # Wait for results
  if (.progress) {
    cat_info("[Wait] Waiting for results...\n")
  }

  results <- vector("list", n)
  completed <- 0
  last_update <- Sys.time()

  while (completed < n) {
    for (i in seq_along(futures)) {
      if (!is.null(results[[i]])) next

      if (resolved(futures[[i]])) {
        result_obj <- result(futures[[i]])

        if (length(result_obj$conditions) > 0) {
          stop(sprintf("Task %d failed: %s", i, result_obj$conditions[[1]]$message))
        }

        results[[i]] <- result_obj$value
        completed <- completed + 1

        if (.progress && (completed == n || difftime(Sys.time(), last_update, units = "secs") >= 2)) {
          elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          cat_info(sprintf("\r[Wait] Progress: %d/%d (%.1fs)   ", completed, n, elapsed))
          last_update <- Sys.time()
        }
      }
    }

    if (completed < n) {
      Sys.sleep(1)
    }
  }

  if (.progress) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat_success(sprintf("\n[OK] Completed in %.1f seconds\n", elapsed))

    # Cost estimate — forward the actual backend/instance/spot so the estimate
    # matches where the job ran (previously always used Fargate defaults).
    cost_est <- estimate_cost(workers, cpu, memory,
                              launch_type = launch_type,
                              instance_type = instance_type,
                              use_spot = use_spot)
    hours <- elapsed / 3600
    est_cost <- cost_est$hourly_rate * hours
    cat_info(sprintf("[Cost] Estimated cost: $%.2f\n", est_cost))
  }

  results
}

#' Create a Starburst Cluster
#'
#' Creates a cluster object for managing AWS workers (EC2 by default, or Fargate)
#' using the staRburst Future backend.
#'
#' @param workers Number of parallel workers
#' @param cpu CPU units per worker
#' @param memory Memory per worker
#' @param region AWS region
#' @param timeout Maximum runtime in seconds
#' @param launch_type Compute backend: "EC2" (default) or "FARGATE"
#' @param instance_type EC2 instance type when \code{launch_type = "EC2"}
#'   (default: "c7g.xlarge"). Worker CPU architecture follows the instance type
#'   (Graviton \code{*g.*} = ARM64, Intel/AMD = x86_64); there is no separate
#'   platform argument.
#' @param use_spot Use EC2 Spot instances for cost savings (default: TRUE)
#'
#' @return A starburst_cluster object
#' @export
#'
#' @examples
#' \donttest{
#' if (starburst_is_configured()) {
#'   cluster <- starburst_cluster(workers = 20)
#'   results <- cluster$map(data, function(x) x * 2)
#'
#'   # Fargate backend instead of the EC2 default
#'   fg <- starburst_cluster(workers = 20, launch_type = "FARGATE")
#' }
#' }
starburst_cluster <- function(workers = 10, cpu = 4, memory = "8GB",
                              region = NULL, timeout = 3600,
                              launch_type = "EC2", instance_type = "c7g.xlarge",
                              use_spot = TRUE) {

  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"

  # Setup the Future plan by calling plan.starburst directly
  strategy <- plan.starburst(
    strategy = starburst,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout,
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot
  )

  future::plan(strategy)

  # Get backend from options (set by plan.starburst)
  backend <- getOption("starburst.current_backend")

  # Create cluster object
  cluster <- list(
    evaluator = backend,
    backend = backend,
    cluster_id = backend$cluster_id,
    workers = backend$workers,
    cpu = backend$cpu,
    memory = backend$memory,
    region = backend$region,
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot,
    created_at = backend$created_at
  )

  # Add methods
  cluster$map <- function(.x, .f, .progress = TRUE) {
    starburst_cluster_map(cluster, .x, .f, .progress)
  }

  cluster$estimate_cost <- function(elapsed_seconds) {
    cost_est <- estimate_cost(cluster$workers, cluster$cpu, cluster$memory,
                              launch_type = cluster$launch_type,
                              instance_type = cluster$instance_type,
                              use_spot = cluster$use_spot)
    hours <- elapsed_seconds / 3600
    cost_est$hourly_rate * hours
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
#' Internal function to execute parallel map by creating StarburstFuture objects directly
#'
#' @keywords internal
starburst_cluster_map <- function(cluster, .x, .f, .progress = TRUE) {

  n <- length(.x)

  if (.progress) {
    cat_info(sprintf("[Status] Processing %d items with %d workers\n", n, cluster$workers))
  }

  start_time <- Sys.time()

  # Create StarburstFuture objects directly for each item
  # This bypasses the Future dispatch issues
  futures <- vector("list", n)

  for (i in seq_along(.x)) {
    # Create a future for this item
    item <- .x[[i]]

    # Create globals list
    globals_list <- list(
      .f = .f,
      .item = item
    )

    futures[[i]] <- StarburstFuture(
      expr = quote(.f(.item)),
      envir = parent.frame(),
      substitute = FALSE,
      globals = globals_list,  # Pass as globals so they get serialized
      packages = NULL
    )
  }

  # Run all futures (submits to AWS)
  if (.progress) {
    cat_info(sprintf("[Starting] Submitting %d tasks to AWS...\n", n))
  }

  for (future in futures) {
    run(future)
  }

  # Wait for all futures to resolve and collect results
  if (.progress) {
    cat_info("[Wait] Waiting for results...\n")
  }

  results <- vector("list", n)
  completed <- 0
  last_update <- Sys.time()

  while (completed < n) {
    for (i in seq_along(futures)) {
      if (!is.null(results[[i]])) next  # Already got result

      if (resolved(futures[[i]])) {
        result_obj <- result(futures[[i]])

        # Check for errors
        if (length(result_obj$conditions) > 0) {
          stop(sprintf("Task %d failed: %s", i, result_obj$conditions[[1]]$message))
        }

        results[[i]] <- result_obj$value
        completed <- completed + 1

        if (.progress && (completed == n || difftime(Sys.time(), last_update, units = "secs") >= 2)) {
          elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          cat_info(sprintf("\r[Wait] Progress: %d/%d tasks (%.1fs elapsed)   ", completed, n, elapsed))
          last_update <- Sys.time()
        }
      }
    }

    if (completed < n) {
      Sys.sleep(1)
    }
  }

  if (.progress) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat_success(sprintf("\n[OK] Completed %d items in %.1f seconds\n", n, elapsed))
  }

  results
}

# Note: %||% operator defined in R/utils.R
