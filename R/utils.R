#' Utility functions for staRburst
#'
#' @keywords internal
NULL

#' Check AWS credentials
#'
#' @return Logical indicating if credentials are valid
#' @keywords internal
check_aws_credentials <- function() {
  tryCatch({
    sts <- paws.management::sts()
    identity <- sts$get_caller_identity()
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Get AWS account ID
#'
#' @return AWS account ID
#' @keywords internal
get_aws_account_id <- function() {
  sts <- paws.management::sts()
  identity <- sts$get_caller_identity()
  identity$Account
}

#' Get S3 client
#'
#' @param region AWS region
#' @return S3 client
#' @keywords internal
get_s3_client <- function(region) {
  paws.storage::s3(config = list(region = region))
}

#' Get ECS client
#'
#' @param region AWS region
#' @return ECS client
#' @keywords internal
get_ecs_client <- function(region) {
  paws.compute::ecs(config = list(region = region))
}

#' Get ECR client
#'
#' @param region AWS region
#' @return ECR client
#' @keywords internal
get_ecr_client <- function(region) {
  paws.compute::ecr(config = list(region = region))
}

#' Get EC2 client
#'
#' @param region AWS region
#' @return EC2 client
#' @keywords internal
get_ec2_client <- function(region) {
  paws.compute::ec2(config = list(region = region))
}

#' Get Service Quotas client
#'
#' @param region AWS region
#' @return Service Quotas client
#' @keywords internal
get_service_quotas_client <- function(region) {
  paws.management::servicequotas(config = list(region = region))
}

#' Get starburst bucket name
#'
#' @return S3 bucket name
#' @keywords internal
get_starburst_bucket <- function() {
  config <- get_starburst_config()
  config$bucket
}

#' Get starburst subnets
#'
#' @param region AWS region
#' @return Vector of subnet IDs
#' @keywords internal
get_starburst_subnets <- function(region) {
  config <- get_starburst_config()
  config$subnets
}

#' Get starburst security groups
#'
#' @param region AWS region
#' @return Vector of security group IDs
#' @keywords internal
get_starburst_security_groups <- function(region) {
  config <- get_starburst_config()
  config$security_groups
}

#' Infix null-coalesce operator
#'
#' @keywords internal
`%||%` <- function(a, b) {
  if (is.null(a)) b else a
}

#' Create task object
#'
#' @keywords internal
create_task <- function(expr, globals, packages, plan) {
  list(
    expr = expr,
    globals = globals,
    packages = packages,
    plan_info = list(
      cluster_id = plan$cluster_id,
      cpu = plan$cpu,
      memory = plan$memory,
      region = plan$region
    )
  )
}

#' Serialize and upload to S3
#'
#' @keywords internal
serialize_and_upload <- function(obj, bucket, key) {
  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file))

  qs::qsave(obj, temp_file)

  s3 <- get_s3_client(extract_region_from_key(key))
  s3$put_object(
    Bucket = bucket,
    Key = key,
    Body = temp_file
  )

  invisible(NULL)
}

#' Extract region from S3 key
#'
#' @keywords internal
extract_region_from_key <- function(key) {
  config <- get_starburst_config()
  config$region
}

#' Check if result exists
#'
#' @keywords internal
result_exists <- function(task_id, region) {
  bucket <- get_starburst_bucket()
  key <- sprintf("results/%s.qs", task_id)

  s3 <- get_s3_client(region)

  tryCatch({
    s3$head_object(Bucket = bucket, Key = key)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Poll for result
#'
#' @keywords internal
poll_for_result <- function(future, timeout = 3600) {
  bucket <- get_starburst_bucket()
  key <- sprintf("results/%s/%s.qs", future$plan$cluster_id, future$task_id)
  region <- future$plan$region

  s3 <- get_s3_client(region)

  start_time <- Sys.time()

  while (TRUE) {
    # Check if result exists
    if (result_exists(future$task_id, region)) {
      # Download and deserialize
      temp_file <- tempfile(fileext = ".qs")
      on.exit(unlink(temp_file))

      s3$download_file(
        Bucket = bucket,
        Key = key,
        Filename = temp_file
      )

      result <- qs::qread(temp_file)
      return(result)
    }

    # Check timeout
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    if (elapsed > timeout) {
      stop(sprintf("Task timeout after %d seconds", timeout))
    }

    # Wait before next poll
    Sys.sleep(2)
  }
}

#' Estimate cost
#'
#' @keywords internal
estimate_cost <- function(workers, cpu, memory, estimated_runtime_hours = 1) {
  # Fargate pricing (us-east-1, 2026)
  vcpu_price_per_hour <- 0.04048
  gb_price_per_hour <- 0.004445

  memory_gb <- parse_memory(memory)

  cost_per_worker_per_hour <-
    (cpu * vcpu_price_per_hour) +
    (memory_gb * gb_price_per_hour)

  list(
    per_worker = cost_per_worker_per_hour,
    per_hour = cost_per_worker_per_hour * workers,
    total_estimated = cost_per_worker_per_hour * workers * estimated_runtime_hours
  )
}

#' Calculate task cost
#'
#' @keywords internal
calculate_task_cost <- function(future) {
  # Get actual runtime
  if (is.null(future$completed_at)) {
    return(0)
  }

  runtime_hours <- as.numeric(
    difftime(future$completed_at, future$submitted_at, units = "hours")
  )

  # Calculate cost
  cost_est <- estimate_cost(1, future$plan$cpu, future$plan$memory, runtime_hours)
  cost_est$total_estimated
}

#' Calculate total cost
#'
#' @keywords internal
calculate_total_cost <- function(plan) {
  ecs <- get_ecs_client(plan$region)

  # Fargate pricing (us-east-1, adjust for other regions)
  # Reference: https://aws.amazon.com/fargate/pricing/
  vcpu_hour_cost <- 0.04048
  gb_hour_cost <- 0.004445

  total_cost <- 0

  tryCatch({
    # Get all task ARNs for this cluster
    task_arns <- list()
    stored_tasks <- list_task_arns()

    for (task_id in names(stored_tasks)) {
      task_arns <- append(task_arns, stored_tasks[[task_id]]$task_arn)
    }

    if (length(task_arns) == 0) {
      return(0)
    }

    # Describe tasks to get runtime information
    # Process in batches of 100 (ECS limit)
    batch_size <- 100
    for (i in seq(1, length(task_arns), by = batch_size)) {
      end_idx <- min(i + batch_size - 1, length(task_arns))
      batch <- task_arns[i:end_idx]

      tasks <- ecs$describe_tasks(
        cluster = "starburst-cluster",
        tasks = batch
      )

      for (task in tasks$tasks) {
        # Calculate runtime
        if (!is.null(task$startedAt)) {
          started <- as.POSIXct(task$startedAt, origin = "1970-01-01")

          stopped <- if (!is.null(task$stoppedAt)) {
            as.POSIXct(task$stoppedAt, origin = "1970-01-01")
          } else {
            Sys.time()  # Still running
          }

          runtime_hours <- as.numeric(difftime(stopped, started, units = "hours"))

          # Calculate cost based on CPU and memory
          vcpu_cost <- runtime_hours * plan$worker_cpu * vcpu_hour_cost
          memory_cost <- runtime_hours * plan$worker_memory * gb_hour_cost

          total_cost <- total_cost + vcpu_cost + memory_cost
        }
      }
    }

    return(total_cost)

  }, error = function(e) {
    # If we can't get actual costs, return tracked estimate
    if (!is.null(plan$total_cost)) {
      return(plan$total_cost)
    }
    return(0)
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

#' Cleanup S3 files
#'
#' @keywords internal
cleanup_s3_files <- function(plan) {
  bucket <- get_starburst_bucket()
  prefix <- sprintf("tasks/%s/", plan$cluster_id)

  s3 <- get_s3_client(plan$region)

  tryCatch({
    # List and delete task files
    objects <- s3$list_objects_v2(Bucket = bucket, Prefix = prefix)

    if (length(objects$Contents) > 0) {
      delete_objects <- lapply(objects$Contents, function(obj) {
        list(Key = obj$Key)
      })

      s3$delete_objects(
        Bucket = bucket,
        Delete = list(Objects = delete_objects)
      )
    }
  }, error = function(e) {
    warning(sprintf("Error cleaning S3 files: %s", e$message))
  })

  invisible(NULL)
}

#' Ensure environment is ready
#'
#' @keywords internal
ensure_environment <- function(region) {
  # Get renv lock file hash
  lock_file <- renv::paths$lockfile()

  if (!file.exists(lock_file)) {
    # Create renv snapshot
    # force = TRUE allows locally installed packages like starburst itself
    renv::snapshot(prompt = FALSE, force = TRUE)
  }

  # Calculate hash
  env_hash <- digest::digest(file = lock_file, algo = "md5")

  # Get configuration for ECR URI
  config <- get_starburst_config()
  account_id <- config$aws_account_id
  ecr_uri <- sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker", account_id, region)
  image_uri <- sprintf("%s:%s", ecr_uri, env_hash)

  # Check if image exists in ECR
  image_exists <- check_ecr_image_exists(env_hash, region)

  if (!image_exists) {
    cat_info("🔧 Building Docker image for R environment (this may take 5-10 minutes)...\n")
    build_environment_image(env_hash, region)
  }

  # Return both hash and image URI
  list(
    hash = env_hash,
    image_uri = image_uri
  )
}

#' Check if ECR image exists
#'
#' @keywords internal
check_ecr_image_exists <- function(tag, region) {
  config <- get_starburst_config()
  ecr <- get_ecr_client(region)

  tryCatch({
    images <- ecr$describe_images(
      repositoryName = "starburst-worker",
      imageIds = list(list(imageTag = tag))
    )

    length(images$imageDetails) > 0
  }, error = function(e) {
    return(FALSE)
  })
}

#' Build environment image
#'
#' @keywords internal
build_environment_image <- function(tag, region) {
  cat_info("🐳 Building Docker image...\n")

  # Validate Docker is installed
  docker_check <- system2("docker", "--version", stdout = TRUE, stderr = TRUE)
  if (attr(docker_check, "status") != 0 && !is.null(attr(docker_check, "status"))) {
    stop("Docker is not installed or not accessible. Please install Docker: https://docs.docker.com/get-docker/")
  }

  # Get configuration
  config <- get_starburst_config()
  account_id <- config$aws_account_id

  # Get ECR repository URI
  ecr_uri <- sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker", account_id, region)

  # Create temporary build directory
  build_dir <- tempfile(pattern = "starburst_build_")
  dir.create(build_dir, recursive = TRUE)
  on.exit(unlink(build_dir, recursive = TRUE), add = TRUE)

  tryCatch({
    # Copy renv.lock from project, excluding staRburst itself
    if (!file.exists("renv.lock")) {
      stop("renv.lock not found in current directory. Initialize renv first with: renv::init()")
    }

    # Read and filter lock file to exclude starburst package
    lock_data <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)
    if (!is.null(lock_data$Packages$starburst)) {
      lock_data$Packages$starburst <- NULL
    }
    jsonlite::write_json(lock_data, file.path(build_dir, "renv.lock"),
                        pretty = TRUE, auto_unbox = TRUE)

    # Copy worker script
    worker_script <- system.file("templates", "worker.R", package = "starburst")
    if (!file.exists(worker_script)) {
      stop("Worker script template not found")
    }
    file.copy(worker_script, file.path(build_dir, "worker.R"))

    # Process Dockerfile template
    dockerfile_template <- system.file("templates", "Dockerfile.template", package = "starburst")
    if (!file.exists(dockerfile_template)) {
      stop("Dockerfile template not found")
    }

    template_content <- readLines(dockerfile_template)
    r_version <- paste0(R.version$major, ".", R.version$minor)
    dockerfile_content <- gsub("\\{\\{R_VERSION\\}\\}", r_version, template_content)
    writeLines(dockerfile_content, file.path(build_dir, "Dockerfile"))

    cat_info(sprintf("   • Build directory: %s\n", build_dir))
    cat_info(sprintf("   • R version: %s\n", r_version))

    # Authenticate with ECR
    cat_info("   • Authenticating with ECR...\n")
    ecr <- get_ecr_client(region)
    auth_token <- ecr$get_authorization_token()

    if (length(auth_token$authorizationData) == 0) {
      stop("Failed to get ECR authorization token")
    }

    token_data <- auth_token$authorizationData[[1]]
    decoded_token <- rawToChar(base64enc::base64decode(token_data$authorizationToken))
    token_parts <- strsplit(decoded_token, ":")[[1]]
    password <- token_parts[2]

    # Docker login
    login_cmd <- sprintf("echo %s | docker login --username AWS --password-stdin %s",
                        shQuote(password), token_data$proxyEndpoint)
    login_result <- system(login_cmd, ignore.stdout = TRUE, ignore.stderr = FALSE)

    if (login_result != 0) {
      stop("Failed to authenticate with ECR")
    }

    # Build image
    image_tag <- sprintf("%s:%s", ecr_uri, tag)
    cat_info(sprintf("   • Building image: %s\n", image_tag))

    build_cmd <- sprintf("docker build --platform linux/amd64 -t %s %s", shQuote(image_tag), shQuote(build_dir))
    build_result <- system(build_cmd)

    if (build_result != 0) {
      stop("Docker build failed")
    }

    # Push image
    cat_info("   • Pushing image to ECR...\n")
    push_cmd <- sprintf("docker push %s", shQuote(image_tag))
    push_result <- system(push_cmd)

    if (push_result != 0) {
      stop("Failed to push image to ECR")
    }

    cat_success(sprintf("✓ Image built and pushed: %s\n", image_tag))

    return(image_tag)

  }, error = function(e) {
    cat_error(sprintf("✗ Image build failed: %s\n", e$message))
    stop(e)
  })
}

#' Build initial environment
#'
#' @keywords internal
build_initial_environment <- function(region) {
  ensure_environment(region)
}

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
  result <- logs$describe_log_groups(logGroupNamePrefix = log_group_name)

  # If log group exists with exact name match, return
  if (length(result$logGroups) > 0) {
    for (lg in result$logGroups) {
      if (lg$logGroupName == log_group_name) {
        return(invisible(NULL))
      }
    }
  }

  # Create log group if it doesn't exist
  tryCatch({
    logs$create_log_group(logGroupName = log_group_name)
    cat_info(sprintf("   • Created log group: %s\n", log_group_name))
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
  cat_info("📋 Preparing task definition...\n")

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

      # Check if CPU, memory, and image match
      if (task_def$cpu == cpu_units &&
          task_def$memory == memory_mb &&
          length(task_def$containerDefinitions) > 0) {

        container_def <- task_def$containerDefinitions[[1]]
        if (container_def$image == plan$image_uri) {
          cat_success(sprintf("✓ Using existing task definition: %s\n", task_def$taskDefinitionArn))
          return(task_def$taskDefinitionArn)
        }
      }
    }
  }, error = function(e) {
    # Continue to create new task definition
  })

  # Create new task definition
  cat_info("   • Registering new task definition...\n")

  container_def <- list(
    name = "starburst-worker",
    image = plan$image_uri,
    memory = as.integer(memory_mb),
    essential = TRUE,
    logConfiguration = list(
      logDriver = "awslogs",
      options = list(
        "awslogs-group" = log_group_name,
        "awslogs-region" = plan$region,
        "awslogs-stream-prefix" = "starburst"
      )
    ),
    environment = list()  # Will be set per task
  )

  response <- ecs$register_task_definition(
    family = family_name,
    networkMode = "awsvpc",
    requiresCompatibilities = list("FARGATE"),
    cpu = cpu_units,
    memory = memory_mb,
    executionRoleArn = execution_role_arn,
    taskRoleArn = task_role_arn,
    containerDefinitions = list(container_def)
  )

  task_def_arn <- response$taskDefinition$taskDefinitionArn
  cat_success(sprintf("✓ Task definition registered: %s\n", task_def_arn))

  return(task_def_arn)
}

#' Get task registry environment
#'
#' @keywords internal
get_task_registry <- function() {
  if (!exists(".starburst_task_registry", envir = .GlobalEnv)) {
    assign(".starburst_task_registry", new.env(parent = emptyenv()), envir = .GlobalEnv)
  }
  get(".starburst_task_registry", envir = .GlobalEnv)
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

#' Get or create subnets
#'
#' @keywords internal
get_or_create_subnets <- function(vpc_id, region) {
  ec2 <- get_ec2_client(region)

  # Check for existing subnets with starburst tag
  subnets <- ec2$describe_subnets(
    Filters = list(
      list(Name = "vpc-id", Values = list(vpc_id)),
      list(Name = "tag:ManagedBy", Values = list("starburst"))
    )
  )

  if (length(subnets$Subnets) > 0) {
    return(sapply(subnets$Subnets, function(s) s$SubnetId))
  }

  # Get existing subnets to check if VPC has any
  all_subnets <- ec2$describe_subnets(
    Filters = list(
      list(Name = "vpc-id", Values = list(vpc_id))
    )
  )

  if (length(all_subnets$Subnets) > 0) {
    # Use existing subnets (don't create new ones unnecessarily)
    return(sapply(all_subnets$Subnets, function(s) s$SubnetId))
  }

  # Create subnets in multiple availability zones
  cat_info("   • Creating subnets for VPC...\n")

  # Get available AZs
  azs <- ec2$describe_availability_zones(
    Filters = list(
      list(Name = "region-name", Values = list(region)),
      list(Name = "state", Values = list("available"))
    )
  )

  if (length(azs$AvailabilityZones) == 0) {
    stop("No availability zones found in region")
  }

  # Create subnets in first 2-3 AZs
  num_subnets <- min(3, length(azs$AvailabilityZones))
  subnet_ids <- character(0)

  for (i in 1:num_subnets) {
    az <- azs$AvailabilityZones[[i]]$ZoneName
    cidr_block <- sprintf("10.0.%d.0/24", i)

    tryCatch({
      subnet <- ec2$create_subnet(
        VpcId = vpc_id,
        CidrBlock = cidr_block,
        AvailabilityZone = az
      )

      subnet_id <- subnet$Subnet$SubnetId

      # Tag subnet
      ec2$create_tags(
        Resources = list(subnet_id),
        Tags = list(
          list(Key = "Name", Value = sprintf("starburst-subnet-%d", i)),
          list(Key = "ManagedBy", Value = "starburst")
        )
      )

      # Enable auto-assign public IP
      ec2$modify_subnet_attribute(
        SubnetId = subnet_id,
        MapPublicIpOnLaunch = list(Value = TRUE)
      )

      subnet_ids <- c(subnet_ids, subnet_id)
      cat_info(sprintf("   • Created subnet: %s in %s\n", subnet_id, az))

    }, error = function(e) {
      cat_warn(sprintf("   • Failed to create subnet in %s: %s\n", az, e$message))
    })
  }

  if (length(subnet_ids) == 0) {
    stop("Failed to create any subnets")
  }

  return(subnet_ids)
}

#' Get or create security group
#'
#' @keywords internal
get_or_create_security_group <- function(vpc_id, region) {
  ec2 <- get_ec2_client(region)

  # Look for existing starburst security group
  sgs <- ec2$describe_security_groups(
    Filters = list(
      list(Name = "vpc-id", Values = list(vpc_id)),
      list(Name = "group-name", Values = list("starburst-worker"))
    )
  )

  if (length(sgs$SecurityGroups) > 0) {
    return(sgs$SecurityGroups[[1]]$GroupId)
  }

  # Create security group
  sg <- ec2$create_security_group(
    GroupName = "starburst-worker",
    Description = "Security group for staRburst workers",
    VpcId = vpc_id
  )

  sg$GroupId
}

#' Get VPC configuration for ECS tasks
#'
#' @keywords internal
get_vpc_config <- function(region) {
  ec2 <- get_ec2_client(region)

  # Get default VPC
  vpcs <- ec2$describe_vpcs(
    Filters = list(
      list(Name = "isDefault", Values = list("true"))
    )
  )

  if (length(vpcs$Vpcs) == 0) {
    stop("No default VPC found. Please create a VPC in region: ", region)
  }

  vpc_id <- vpcs$Vpcs[[1]]$VpcId

  # Get or create subnets
  subnets <- get_or_create_subnets(vpc_id, region)

  if (length(subnets) == 0) {
    stop("Failed to create subnets in VPC: ", vpc_id)
  }

  # Get or create security group
  sg_id <- get_or_create_security_group(vpc_id, region)

  list(
    vpc_id = vpc_id,
    subnets = as.list(subnets),
    security_groups = list(sg_id)
  )
}
