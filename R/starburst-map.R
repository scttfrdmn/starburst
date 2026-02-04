#' Map Function Over Data Using AWS Fargate
#'
#' Parallel map function that executes on AWS Fargate
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

  # Convert function arguments
  if (length(list(...)) > 0) {
    extra_args <- list(...)
    .f <- function(x) {
      do.call(.f_orig, c(list(x), extra_args))
    }
    environment(.f)$.f_orig <- .f
  }

  # Setup cluster
  if (.progress) {
    cat_info(sprintf("🚀 Starting starburst cluster with %d workers\n", workers))
  }

  cluster <- starburst_cluster(
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout
  )

  # Execute map
  tryCatch({
    results <- cluster$map(.x, .f, .progress = .progress)
    results
  }, finally = {
    if (.progress) {
      # Print summary
      elapsed <- as.numeric(difftime(Sys.time(), cluster$created_at, units = "secs"))
      cat_success(sprintf("\n✓ Completed in %.1f seconds\n", elapsed))

      # Cost estimate
      cost <- cluster$estimate_cost(elapsed)
      cat_info(sprintf("💰 Estimated cost: $%.2f\n", cost))
    }
  })
}

#' Create a Starburst Cluster
#'
#' Creates a cluster object for managing AWS Fargate workers
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

  # Check quota
  quota_info <- check_fargate_quota(region)
  vcpus_needed <- workers * cpu
  vcpus_available <- quota_info$limit

  if (vcpus_needed > vcpus_available) {
    workers_available <- floor(vcpus_available / cpu)
    cat_warn(sprintf(
      "⚠ Requested %d workers (%d vCPUs) but quota allows %d workers (%d vCPUs)\n",
      workers, vcpus_needed, workers_available, vcpus_available
    ))
    cat_warn(sprintf("⚠ Using %d workers instead\n", workers_available))
    workers <- workers_available
  }

  # Estimate cost
  cost_est <- estimate_cost(workers, cpu, memory)
  cat_info(sprintf("💰 Estimated cost: ~$%.2f/hour\n", cost_est$per_hour))

  # Ensure environment is ready
  cat_info("🔧 Preparing execution environment...\n")
  env_info <- ensure_environment(region)

  # Create cluster object
  cluster_id <- sprintf("starburst-%s", gsub("-", "", uuid::UUIDgenerate()))

  cluster <- list(
    cluster_id = cluster_id,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    bucket = config$bucket,
    timeout = timeout,
    image_uri = env_info$image_uri,
    env_hash = env_info$hash,
    task_definition_arn = NULL,
    created_at = Sys.time(),
    tasks = list()
  )

  # Add methods
  cluster$map <- function(.x, .f, .progress = TRUE) {
    starburst_cluster_map(cluster, .x, .f, .progress)
  }

  cluster$estimate_cost <- function(elapsed_seconds) {
    hours <- elapsed_seconds / 3600
    cost_est$per_hour * hours
  }

  class(cluster) <- "starburst_cluster"

  cat_success(sprintf("✓ Cluster ready: %s\n", cluster_id))

  cluster
}

#' Execute Map on Starburst Cluster
#'
#' Internal function to execute parallel map
#'
#' @keywords internal
starburst_cluster_map <- function(cluster, .x, .f, .progress = TRUE) {

  n <- length(.x)

  if (.progress) {
    cat_info(sprintf("📊 Processing %d items with %d workers\n", n, cluster$workers))
  }

  # Split data into chunks for workers
  chunk_size <- ceiling(n / cluster$workers)
  chunks <- split(.x, ceiling(seq_along(.x) / chunk_size))

  if (.progress) {
    cat_info(sprintf("📦 Created %d chunks (avg %d items per chunk)\n",
                    length(chunks), chunk_size))
  }

  # Ensure task definition exists
  if (is.null(cluster$task_definition_arn)) {
    if (.progress) cat_info("📋 Creating task definition...\n")
    cluster$task_definition_arn <- get_or_create_task_definition(cluster)
  }

  # Submit all chunks as tasks
  if (.progress) cat_info("🚀 Submitting tasks...\n")

  task_ids <- vector("list", length(chunks))
  for (i in seq_along(chunks)) {
    task_id <- submit_chunk_task(cluster, chunks[[i]], .f, i)
    task_ids[[i]] <- task_id
    cluster$tasks[[task_id]] <- list(
      chunk_index = i,
      chunk_size = length(chunks[[i]]),
      submitted_at = Sys.time(),
      state = "running"
    )
  }

  if (.progress) {
    cat_success(sprintf("✓ Submitted %d tasks\n", length(chunks)))
  }

  # Poll for results
  results <- poll_all_results(cluster, task_ids, .progress)

  # Combine results in correct order
  combined <- do.call(c, lapply(seq_along(chunks), function(i) {
    results[[i]]
  }))

  combined
}

#' Submit a Chunk Task
#'
#' @keywords internal
submit_chunk_task <- function(cluster, chunk, fn, chunk_index) {

  task_id <- sprintf("%s-chunk%d", cluster$cluster_id, chunk_index)

  # Serialize task data
  task_data <- list(
    chunk = chunk,
    fn = fn,
    chunk_index = chunk_index
  )

  # Upload to S3
  s3 <- get_s3_client(cluster$region)
  task_key <- sprintf("tasks/%s.qs", task_id)
  temp_file <- tempfile(fileext = ".qs")

  tryCatch({
    qs::qsave(task_data, temp_file)
    s3$put_object(
      Bucket = cluster$bucket,
      Key = task_key,
      Body = temp_file
    )
  }, finally = {
    unlink(temp_file)
  })

  # Submit ECS task
  ecs <- get_ecs_client(cluster$region)
  vpc_config <- get_vpc_config(cluster$region)

  response <- ecs$run_task(
    cluster = "default",
    taskDefinition = cluster$task_definition_arn,
    launchType = "FARGATE",
    networkConfiguration = list(
      awsvpcConfiguration = list(
        subnets = vpc_config$subnets,
        securityGroups = vpc_config$security_groups,
        assignPublicIp = "ENABLED"
      )
    ),
    overrides = list(
      containerOverrides = list(
        list(
          name = "starburst-worker",
          environment = list(
            list(name = "TASK_ID", value = task_id),
            list(name = "S3_BUCKET", value = cluster$bucket),
            list(name = "AWS_DEFAULT_REGION", value = cluster$region),
            list(name = "CLUSTER_ID", value = cluster$cluster_id)
          )
        )
      )
    )
  )

  if (length(response$tasks) == 0) {
    failure_msg <- if (length(response$failures) > 0) {
      sprintf("%s: %s", response$failures[[1]]$reason, response$failures[[1]]$detail)
    } else {
      "Unknown reason"
    }
    stop(sprintf("Failed to submit task %s: %s", task_id, failure_msg))
  }

  task_id
}

#' Poll for All Results
#'
#' @keywords internal
poll_all_results <- function(cluster, task_ids, .progress = TRUE) {

  n_tasks <- length(task_ids)
  results <- vector("list", n_tasks)
  completed <- rep(FALSE, n_tasks)

  s3 <- get_s3_client(cluster$region)

  start_time <- Sys.time()
  last_update <- start_time

  if (.progress) {
    cat_info("⏳ Waiting for results...\n")
  }

  while (!all(completed)) {
    for (i in seq_along(task_ids)) {
      if (completed[i]) next

      task_id <- task_ids[[i]]
      result_key <- sprintf("results/%s.qs", task_id)

      # Try to download result
      result_exists <- tryCatch({
        temp_file <- tempfile(fileext = ".qs")
        s3$download_file(
          Bucket = cluster$bucket,
          Key = result_key,
          Filename = temp_file
        )
        result_data <- qs::qread(temp_file)
        unlink(temp_file)

        # Check for errors
        if (!is.null(result_data$error) && result_data$error) {
          stop(sprintf("Task %s failed: %s", task_id, result_data$message))
        }

        results[[i]] <- result_data$value
        completed[i] <- TRUE
        TRUE
      }, error = function(e) {
        FALSE
      })
    }

    # Progress update
    if (.progress) {
      now <- Sys.time()
      if (difftime(now, last_update, units = "secs") >= 2 || all(completed)) {
        n_completed <- sum(completed)
        elapsed <- as.numeric(difftime(now, start_time, units = "secs"))
        cat_info(sprintf("\r⏳ Progress: %d/%d tasks (%.1fs elapsed)   ",
                        n_completed, n_tasks, elapsed))
        last_update <- now
      }
    }

    # Check timeout
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    if (elapsed > cluster$timeout) {
      n_completed <- sum(completed)
      stop(sprintf("Timeout: Only %d/%d tasks completed in %d seconds",
                   n_completed, n_tasks, cluster$timeout))
    }

    if (!all(completed)) {
      Sys.sleep(2)
    }
  }

  if (.progress) {
    cat("\n")
  }

  results
}

#' Null-coalescing operator
#' @keywords internal
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
