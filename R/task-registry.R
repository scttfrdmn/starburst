#' In-memory task ARN registry and ECS task listing for staRburst
#'
#' Tracks the ECS task ARNs submitted during a session and provides helpers to
#' list active clusters and stop running tasks.
#'
#' @name task-registry
#' @keywords internal
NULL

#' Get task registry environment
#'
#' @keywords internal
get_task_registry <- function() {
  if (!exists(".starburst_task_registry", envir = .starburst_env)) {
    assign(".starburst_task_registry", new.env(parent = emptyenv()), envir = .starburst_env)
  }
  get(".starburst_task_registry", envir = .starburst_env)
}

#' Store task ARN
#'
#' @keywords internal
store_task_arn <- function(task_id, task_arn) {
  registry <- get_task_registry()
  registry[[task_id]] <- list(
    task_arn = task_arn,
    submitted_at = Sys.time()
  )
  invisible(NULL)
}

#' Get task ARN
#'
#' @keywords internal
get_task_arn <- function(task_id) {
  registry <- get_task_registry()
  if (exists(task_id, envir = registry)) {
    registry[[task_id]]$task_arn
  } else {
    NULL
  }
}

#' List all stored task ARNs
#'
#' @keywords internal
list_task_arns <- function() {
  registry <- get_task_registry()
  task_ids <- ls(registry)
  if (length(task_ids) == 0) {
    return(list())
  }

  result <- list()
  for (task_id in task_ids) {
    result[[task_id]] <- registry[[task_id]]
  }
  result
}

#' List active clusters
#'
#' @keywords internal
list_active_clusters <- function(region) {
  ecs <- get_ecs_client(region)

  tryCatch({
    # List all running tasks in the starburst cluster
    task_list <- ecs$list_tasks(
      cluster = "starburst-cluster",
      desiredStatus = "RUNNING"
    )

    if (length(task_list$taskArns) == 0) {
      return(list())
    }

    # Describe tasks to get details
    tasks <- ecs$describe_tasks(
      cluster = "starburst-cluster",
      tasks = task_list$taskArns
    )

    # Group by cluster ID from environment variables
    clusters <- list()

    for (task in tasks$tasks) {
      # Extract CLUSTER_ID from environment variables
      cluster_id <- NULL
      if (!is.null(task$overrides) && !is.null(task$overrides$containerOverrides)) {
        for (container in task$overrides$containerOverrides) {
          if (!is.null(container$environment)) {
            for (env_var in container$environment) {
              if (env_var$name == "CLUSTER_ID") {
                cluster_id <- env_var$value
                break
              }
            }
          }
          if (!is.null(cluster_id)) break
        }
      }

      if (!is.null(cluster_id)) {
        if (is.null(clusters[[cluster_id]])) {
          clusters[[cluster_id]] <- list(
            cluster_id = cluster_id,
            task_count = 0,
            tasks = list()
          )
        }

        clusters[[cluster_id]]$task_count <- clusters[[cluster_id]]$task_count + 1
        clusters[[cluster_id]]$tasks <- append(
          clusters[[cluster_id]]$tasks,
          list(list(
            task_arn = task$taskArn,
            started_at = task$startedAt,
            status = task$lastStatus
          ))
        )
      }
    }

    return(clusters)

  }, error = function(e) {
    # Return empty list if cluster doesn't exist or other error
    return(list())
  })
}

#' Stop running tasks
#'
#' @keywords internal
stop_running_tasks <- function(plan) {
  ecs <- get_ecs_client(plan$region)

  tryCatch({
    # List running tasks
    tasks <- ecs$list_tasks(
      cluster = "starburst-cluster",
      family = "starburst-worker"
    )

    # Stop each task
    for (task_arn in tasks$taskArns) {
      ecs$stop_task(
        cluster = "starburst-cluster",
        task = task_arn,
        reason = "Cluster cleanup"
      )
    }
  }, error = function(e) {
    warning(sprintf("Error stopping tasks: %s", e$message))
  })

  invisible(NULL)
}
