#' ECS task definitions, IAM roles, and log groups for staRburst
#'
#' @name task-definition
#' @keywords internal
NULL

#' Ensure CloudWatch log group exists
#'
#' @keywords internal
ensure_log_group <- function(log_group_name, region) {
  logs <- paws.management::cloudwatchlogs(
    config = list(
      credentials = list(profile = Sys.getenv("AWS_PROFILE", "default")),
      region = region
    )
  )

  # Check if log group exists
  log_group_exists <- FALSE
  tryCatch({
    result <- logs$describe_log_groups(logGroupNamePrefix = log_group_name)

    # If log group exists with exact name match, return
    if (length(result$logGroups) > 0) {
      for (lg in result$logGroups) {
        if (lg$logGroupName == log_group_name) {
          log_group_exists <- TRUE
          break
        }
      }
    }
  }, error = function(e) {
    # ResourceNotFoundException means log group doesn't exist
    if (grepl("ResourceNotFoundException", e$message)) {
      log_group_exists <<- FALSE
    } else {
      stop(e)
    }
  })

  if (log_group_exists) {
    return(invisible(NULL))
  }

  # Create log group if it doesn't exist
  tryCatch({
    logs$create_log_group(logGroupName = log_group_name)
    cat_info(sprintf("   * Created log group: %s\n", log_group_name))
  }, error = function(e) {
    # Ignore if already exists
    if (!grepl("ResourceAlreadyExistsException", e$message)) {
      stop(e)
    }
  })
}

#' Get IAM execution role ARN
#'
#' Returns the ARN for the ECS execution role (should be created during setup)
#'
#' @keywords internal
get_execution_role_arn <- function(region) {
  config <- get_starburst_config()

  # Use role from config if available
  if (!is.null(config$execution_role_arn)) {
    return(config$execution_role_arn)
  }

  # Return default role ARN
  aws_account_id <- config$aws_account_id
  role_name <- "starburstECSExecutionRole"

  sprintf("arn:aws:iam::%s:role/%s", aws_account_id, role_name)
}

#' Get IAM task role ARN
#'
#' Returns the ARN for the ECS task role (should be created during setup)
#'
#' @keywords internal
get_task_role_arn <- function(region) {
  config <- get_starburst_config()

  # Use role from config if available
  if (!is.null(config$task_role_arn)) {
    return(config$task_role_arn)
  }

  # Return default role ARN
  aws_account_id <- config$aws_account_id
  role_name <- "starburstECSTaskRole"

  sprintf("arn:aws:iam::%s:role/%s", aws_account_id, role_name)
}

#' Get or create task definition
#'
#' @keywords internal
get_or_create_task_definition <- function(plan) {
  cat_info("[Info] Preparing task definition...\n")

  ecs <- get_ecs_client(plan$region)
  config <- get_starburst_config()

  # Calculate CPU and memory in ECS units
  # CPU: 1 vCPU = 1024 units
  cpu <- plan$cpu %||% plan$worker_cpu
  cpu_units <- as.character(as.integer(cpu * 1024))

  # Memory in MB (parse from string like "8GB")
  memory <- plan$memory %||% plan$worker_memory
  if (is.character(memory)) {
    memory <- as.numeric(gsub("[^0-9.]", "", memory))
  }
  memory_mb <- as.character(as.integer(memory * 1024))

  # Ensure log group exists
  log_group_name <- "/aws/ecs/starburst-worker"
  ensure_log_group(log_group_name, plan$region)

  # Get IAM roles
  execution_role_arn <- get_execution_role_arn(plan$region)
  task_role_arn <- get_task_role_arn(plan$region)

  # Check for existing compatible task definition
  family_name <- "starburst-worker"

  tryCatch({
    task_defs <- ecs$list_task_definitions(
      familyPrefix = family_name,
      status = "ACTIVE",
      sort = "DESC",
      maxResults = 10
    )

    # Check if any existing task definition matches our requirements
    for (task_def_arn in task_defs$taskDefinitionArns) {
      task_def <- ecs$describe_task_definition(taskDefinition = task_def_arn)$taskDefinition

      # Check if CPU, memory, image, and launch type match
      if (task_def$cpu == cpu_units &&
          task_def$memory == memory_mb &&
          length(task_def$containerDefinitions) > 0) {

        # Check image
        container_def <- task_def$containerDefinitions[[1]]
        if (container_def$image != plan$image_uri) {
          next
        }

        # Check launch type compatibility
        launch_type <- plan$launch_type %||% "FARGATE"
        compatibilities <- task_def$requiresCompatibilities %||% list()

        if (!launch_type %in% compatibilities) {
          next
        }

        # For EC2, also check runtimePlatform matches
        if (launch_type == "EC2") {
          expected_arch <- plan$architecture %||% "X86_64"
          actual_arch <- task_def$runtimePlatform$cpuArchitecture %||% "X86_64"

          if (actual_arch != expected_arch) {
            next
          }
        }

        cat_success(sprintf("[OK] Using existing task definition: %s\n", task_def$taskDefinitionArn))
        return(task_def$taskDefinitionArn)
      }
    }
  }, error = function(e) {
    # Continue to create new task definition
  })

  # Create new task definition
  cat_info("   * Registering new task definition...\n")
  cat_info(sprintf("     CPU: %s units, Memory: %s MB\n", cpu_units, memory_mb))

  # For Fargate, container-level memory can be omitted if task-level memory is set
  # But we'll include it to ensure proper resource allocation
  container_memory <- as.integer(memory_mb)

  container_def <- list(
    name = "starburst-worker",
    image = plan$image_uri,
    cpu = 0,  # Not specifying container-level CPU for Fargate
    memory = container_memory,
    essential = TRUE,
    environment = list(),  # Empty environment variables
    logConfiguration = list(
      logDriver = "awslogs",
      options = list(
        "awslogs-group" = log_group_name,
        "awslogs-region" = plan$region,
        "awslogs-stream-prefix" = "starburst"
      )
    )
  )

  cat_info(sprintf("     Container memory: %d MB\n", container_memory))

  # Build task definition parameters
  task_def_params <- list(
    family = family_name,
    networkMode = "awsvpc",
    cpu = cpu_units,
    memory = memory_mb,
    executionRoleArn = execution_role_arn,
    taskRoleArn = task_role_arn,
    containerDefinitions = list(container_def)
  )

  # Add launch type specific parameters
  if (!is.null(plan$launch_type) && plan$launch_type == "EC2") {
    task_def_params$requiresCompatibilities <- list("EC2")
    task_def_params$runtimePlatform <- list(
      cpuArchitecture = plan$architecture,
      operatingSystemFamily = "LINUX"
    )
    cat_info(sprintf("     Launch type: EC2, Architecture: %s\n", plan$architecture))
  } else {
    task_def_params$requiresCompatibilities <- list("FARGATE")
    cat_info("     Launch type: FARGATE\n")
  }

  response <- do.call(ecs$register_task_definition, task_def_params)

  task_def_arn <- response$taskDefinition$taskDefinitionArn
  cat_success(sprintf("[OK] Task definition registered: %s\n", task_def_arn))

  return(task_def_arn)
}
