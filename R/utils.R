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
    sts <- paws.security.identity::sts()
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
  sts <- paws.security.identity::sts()
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

#' Create ECR lifecycle policy to auto-delete old images
#'
#' @param region AWS region
#' @param repository_name ECR repository name
#' @param ttl_days Number of days to keep images (NULL = no auto-delete)
#' @keywords internal
create_ecr_lifecycle_policy <- function(region, repository_name, ttl_days = NULL) {
  if (is.null(ttl_days)) {
    return(invisible(NULL))
  }

  ecr <- get_ecr_client(region)

  # Create lifecycle policy that deletes images older than ttl_days
  # This runs automatically in AWS - no starburst needed
  policy <- list(
    rules = list(
      list(
        rulePriority = 1L,
        description = sprintf("Auto-delete starburst images after %d days of no use", ttl_days),
        selection = list(
          tagStatus = "any",
          countType = "sinceImagePushed",
          countUnit = "days",
          countNumber = as.integer(ttl_days)
        ),
        action = list(
          type = "expire"
        )
      )
    )
  )

  tryCatch({
    ecr$put_lifecycle_policy(
      repositoryName = repository_name,
      lifecyclePolicyText = jsonlite::toJSON(policy, auto_unbox = TRUE)
    )
    cat_success(sprintf("✓ ECR auto-cleanup enabled: Images deleted after %d days\n", ttl_days))
  }, error = function(e) {
    cat_warning(sprintf("⚠ Failed to set ECR lifecycle policy: %s\n", e$message))
  })
}

#' Check ECR image age and suggest/force rebuild
#'
#' @param region AWS region
#' @param image_tag Image tag to check
#' @param ttl_days TTL setting (NULL = no check)
#' @param force_rebuild Force rebuild if past TTL
#' @return TRUE if image is fresh or doesn't exist, FALSE if stale
#' @keywords internal
check_ecr_image_age <- function(region, image_tag, ttl_days = NULL, force_rebuild = FALSE) {
  if (is.null(ttl_days)) {
    return(TRUE)  # No TTL, always consider fresh
  }

  ecr <- get_ecr_client(region)
  config <- get_starburst_config()
  repo_name <- "starburst-worker"

  # Get image details
  image_exists <- tryCatch({
    result <- ecr$describe_images(
      repositoryName = repo_name,
      imageIds = list(list(imageTag = image_tag))
    )
    length(result$imageDetails) > 0
  }, error = function(e) {
    FALSE
  })

  if (!image_exists) {
    return(TRUE)  # Image doesn't exist, will be built
  }

  # Get image push timestamp
  image_details <- ecr$describe_images(
    repositoryName = repo_name,
    imageIds = list(list(imageTag = image_tag))
  )$imageDetails[[1]]

  push_time <- image_details$imagePushedAt
  age_days <- as.numeric(difftime(Sys.time(), push_time, units = "days"))

  # Check if image is stale
  if (age_days > ttl_days) {
    if (force_rebuild) {
      cat_warning(sprintf("⚠ Image is %.0f days old (TTL: %d days), rebuilding...\n",
                         age_days, ttl_days))
      return(FALSE)  # Signal rebuild needed
    } else {
      cat_warning(sprintf("⚠ Image is %.0f days old (TTL: %d days)\n", age_days, ttl_days))
      cat_info("  AWS will auto-delete soon. Consider running a job to refresh.\n")
      return(TRUE)  # Use existing but warn
    }
  } else {
    days_remaining <- ttl_days - age_days
    cat_info(sprintf("✓ Image age: %.0f days (%.0f days until auto-delete)\n",
                    age_days, days_remaining))
    return(TRUE)
  }
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
estimate_cost <- function(workers, cpu, memory, estimated_runtime_hours = 1,
                         launch_type = "FARGATE", instance_type = NULL, use_spot = FALSE) {

  if (launch_type == "FARGATE") {
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
  } else {
    # EC2 pricing
    instance_price <- get_ec2_instance_price(instance_type, use_spot)
    instance_vcpus <- get_instance_vcpus(instance_type)

    # Calculate number of instances needed
    total_vcpus_needed <- workers * cpu
    instances_needed <- ceiling(total_vcpus_needed / instance_vcpus)

    total_cost_per_hour <- instances_needed * instance_price

    list(
      per_instance = instance_price,
      instances_needed = instances_needed,
      total_per_hour = total_cost_per_hour,
      total_estimated = total_cost_per_hour * estimated_runtime_hours,
      spot_discount = if (use_spot) "~70%" else "N/A",
      launch_type = "EC2"
    )
  }
}

#' Get EC2 instance pricing
#'
#' @param instance_type EC2 instance type (e.g., "c7g.xlarge")
#' @param use_spot Whether to use spot pricing
#' @return Price per hour in USD
#' @keywords internal
get_ec2_instance_price <- function(instance_type, use_spot = FALSE) {
  # Simplified pricing table for common instance types (us-east-1, 2026)
  # In production, this could query AWS Pricing API
  pricing <- list(
    # Graviton3 (ARM64) - 7th gen
    "c7g.large" = 0.0725,
    "c7g.xlarge" = 0.145,
    "c7g.2xlarge" = 0.29,
    "c7g.4xlarge" = 0.58,
    "c7g.8xlarge" = 1.16,
    "c7g.12xlarge" = 1.74,
    "c7g.16xlarge" = 2.32,
    "r7g.large" = 0.1008,
    "r7g.xlarge" = 0.2016,
    "r7g.2xlarge" = 0.4032,
    "r7g.4xlarge" = 0.8064,
    "m7g.large" = 0.0816,
    "m7g.xlarge" = 0.1632,
    "m7g.2xlarge" = 0.3264,
    "t4g.small" = 0.0168,
    "t4g.medium" = 0.0336,
    "t4g.large" = 0.0672,

    # AMD 8th gen (x86_64) - BEST OVERALL PRICE/PERFORMANCE (Feb 2026)
    "c8a.large" = 0.072,
    "c8a.xlarge" = 0.144,
    "c8a.2xlarge" = 0.288,
    "c8a.4xlarge" = 0.576,
    "c8a.8xlarge" = 1.152,
    "c8a.12xlarge" = 1.728,
    "c8a.16xlarge" = 2.304,
    "c8a.24xlarge" = 3.456,
    "c8a.32xlarge" = 4.608,
    "r8a.large" = 0.1008,
    "r8a.xlarge" = 0.2016,
    "r8a.2xlarge" = 0.4032,
    "r8a.4xlarge" = 0.8064,
    "m8a.large" = 0.0816,
    "m8a.xlarge" = 0.1632,
    "m8a.2xlarge" = 0.3264,

    # Graviton4 (ARM64) - 8th gen - Second best price/performance
    "c8g.large" = 0.076,
    "c8g.xlarge" = 0.152,
    "c8g.2xlarge" = 0.304,
    "c8g.4xlarge" = 0.608,
    "c8g.8xlarge" = 1.216,
    "c8g.12xlarge" = 1.824,
    "c8g.16xlarge" = 2.432,
    "r8g.large" = 0.1058,
    "r8g.xlarge" = 0.2116,
    "r8g.2xlarge" = 0.4232,
    "r8g.4xlarge" = 0.8464,
    "m8g.large" = 0.0856,
    "m8g.xlarge" = 0.1712,
    "m8g.2xlarge" = 0.3424,

    # Intel 7th gen (x86_64) - Ice Lake
    "c7i.large" = 0.0893,
    "c7i.xlarge" = 0.1785,
    "c7i.2xlarge" = 0.357,
    "c7i.4xlarge" = 0.714,
    "c7i.8xlarge" = 1.428,
    "c7i.12xlarge" = 2.142,
    "c7i.16xlarge" = 2.856,
    "c6i.large" = 0.085,
    "c6i.xlarge" = 0.17,
    "c6i.2xlarge" = 0.34,
    "c6i.4xlarge" = 0.68,
    "r6i.large" = 0.126,
    "r6i.xlarge" = 0.252,
    "r6i.2xlarge" = 0.504,
    "r6i.4xlarge" = 1.008,
    "m6i.large" = 0.096,
    "m6i.xlarge" = 0.192,
    "m6i.2xlarge" = 0.384,

    # Intel 8th gen (x86_64) - Sapphire Rapids - Highest single-thread performance
    "c8i.large" = 0.0935,
    "c8i.xlarge" = 0.187,
    "c8i.2xlarge" = 0.374,
    "c8i.4xlarge" = 0.748,
    "c8i.8xlarge" = 1.496,
    "c8i.12xlarge" = 2.244,
    "c8i.16xlarge" = 2.992,

    # AMD 7th gen (x86_64) - Best price/performance for x86
    "c7a.large" = 0.0765,
    "c7a.xlarge" = 0.153,
    "c7a.2xlarge" = 0.306,
    "c7a.4xlarge" = 0.612,
    "c7a.8xlarge" = 1.224,
    "c7a.12xlarge" = 1.836,
    "c7a.16xlarge" = 2.448,
    "r7a.large" = 0.1134,
    "r7a.xlarge" = 0.2268,
    "r7a.2xlarge" = 0.4536,
    "r7a.4xlarge" = 0.9072,
    "m7a.large" = 0.0864,
    "m7a.xlarge" = 0.1728,
    "m7a.2xlarge" = 0.3456,

    # AMD 6th gen (x86_64) - Good budget option
    "c6a.large" = 0.0765,
    "c6a.xlarge" = 0.153,
    "c6a.2xlarge" = 0.306,
    "c6a.4xlarge" = 0.612,
    "r6a.large" = 0.1134,
    "r6a.xlarge" = 0.2268,
    "r6a.2xlarge" = 0.4536,
    "m6a.large" = 0.0864,
    "m6a.xlarge" = 0.1728,
    "m6a.2xlarge" = 0.3456
  )

  on_demand_price <- pricing[[instance_type]]

  if (is.null(on_demand_price)) {
    # Default estimate if instance type not in table
    cat_warn(sprintf("Warning: No pricing data for %s, using estimate\n", instance_type))
    on_demand_price <- 0.15  # Conservative estimate
  }

  if (use_spot) {
    # Spot instances typically 70% cheaper
    return(on_demand_price * 0.3)
  } else {
    return(on_demand_price)
  }
}

#' Get vCPU count for instance type
#'
#' @param instance_type EC2 instance type
#' @return Number of vCPUs
#' @keywords internal
get_instance_vcpus <- function(instance_type) {
  # Parse instance size to determine vCPUs
  # Format: family + generation + size (e.g., c7g.xlarge)
  size_mapping <- list(
    "nano" = 0.25,
    "micro" = 0.5,
    "small" = 1,
    "medium" = 2,
    "large" = 2,
    "xlarge" = 4,
    "2xlarge" = 8,
    "4xlarge" = 16,
    "8xlarge" = 32,
    "12xlarge" = 48,
    "16xlarge" = 64,
    "24xlarge" = 96,
    "32xlarge" = 128
  )

  # Extract size from instance type
  parts <- strsplit(instance_type, "\\.")[[1]]
  if (length(parts) < 2) {
    stop(sprintf("Invalid instance type format: %s", instance_type))
  }

  size <- parts[2]
  vcpus <- size_mapping[[size]]

  if (is.null(vcpus)) {
    stop(sprintf("Unknown instance size: %s", size))
  }

  return(vcpus)
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

  # Get cluster name from config
  cluster <- config$cluster %||% "starburst-cluster"

  # Return environment info
  list(
    hash = env_hash,
    image_uri = image_uri,
    cluster = cluster
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

#' Get base image URI
#'
#' @keywords internal
get_base_image_uri <- function(region) {
  config <- get_starburst_config()
  account_id <- config$aws_account_id
  r_version <- paste0(R.version$major, ".", R.version$minor)

  # Use base image tag based on R version
  base_tag <- sprintf("base-%s", r_version)

  sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker:%s",
          account_id, region, base_tag)
}

#' Get CPU architecture from instance type
#'
#' @param instance_type EC2 instance type (e.g., "c7g.xlarge", "c7i.xlarge", "c7a.xlarge")
#' @return CPU architecture ("ARM64" or "X86_64")
#' @keywords internal
get_architecture_from_instance_type <- function(instance_type) {
  # Graviton instances end with 'g' in the instance family
  # Examples: c7g/c8g (Graviton3/4), t4g, r7g/r8g, m7g/m8g
  #
  # Intel/AMD instances use other suffixes:
  # - 'i' = Intel (c7i, c8i)
  # - 'a' = AMD (c8a, c7a, c6a - 8th/7th/6th gen)
  # - 'n' = Network optimized
  #
  # Best price/performance (Feb 2026): c8a > c8g > c7a
  if (grepl("^[cmrt][0-9]+g\\.", instance_type)) {
    return("ARM64")
  } else {
    return("X86_64")
  }
}

#' Get instance specifications (vCPUs, memory)
#'
#' @keywords internal
get_instance_specs <- function(instance_type) {
  # Common instance type specs
  # Format: "family.size" -> c(vcpus, memory_gb)
  specs_map <- list(
    # C6a (AMD, 3rd gen EPYC)
    "c6a.large" = c(2, 4),
    "c6a.xlarge" = c(4, 8),
    "c6a.2xlarge" = c(8, 16),
    "c6a.4xlarge" = c(16, 32),
    # C7a (AMD, 4th gen EPYC)
    "c7a.large" = c(2, 4),
    "c7a.xlarge" = c(4, 8),
    "c7a.2xlarge" = c(8, 16),
    "c7a.4xlarge" = c(16, 32),
    # C7g (Graviton3)
    "c7g.large" = c(2, 4),
    "c7g.xlarge" = c(4, 8),
    "c7g.2xlarge" = c(8, 16),
    "c7g.4xlarge" = c(16, 32),
    # C7i (Intel)
    "c7i.large" = c(2, 4),
    "c7i.xlarge" = c(4, 8),
    "c7i.2xlarge" = c(8, 16),
    "c7i.4xlarge" = c(16, 32)
  )

  if (!instance_type %in% names(specs_map)) {
    stop(sprintf("Unknown instance type: %s. Supported types: %s",
                 instance_type, paste(names(specs_map), collapse=", ")))
  }

  specs <- specs_map[[instance_type]]
  list(
    vcpus = specs[1],
    memory_gb = specs[2]
  )
}

#' Build base Docker image with common dependencies
#'
#' @keywords internal
build_base_image <- function(region) {
  cat_info("🐳 Building staRburst base image...\n")

  # Validate Docker is installed
  docker_check <- system2("docker", "--version", stdout = TRUE, stderr = TRUE)
  if (attr(docker_check, "status") != 0 && !is.null(attr(docker_check, "status"))) {
    stop("Docker is not installed or not accessible. Please install Docker: https://docs.docker.com/get-docker/")
  }

  # Get configuration
  config <- get_starburst_config()
  account_id <- config$aws_account_id
  r_version <- paste0(R.version$major, ".", R.version$minor)
  base_tag <- sprintf("base-%s", r_version)

  # Check if base image already exists
  if (check_ecr_image_exists(base_tag, region)) {
    base_uri <- get_base_image_uri(region)

    # Check image age if TTL is configured
    ttl_days <- config$ecr_image_ttl_days
    if (!is.null(ttl_days)) {
      image_fresh <- check_ecr_image_age(region, base_tag, ttl_days, force_rebuild = FALSE)
      if (!image_fresh) {
        cat_info("   • Image expired, rebuilding...\n")
        # Continue to rebuild below
      } else {
        cat_success(sprintf("✓ Base image already exists: %s\n", base_uri))
        return(base_uri)
      }
    } else {
      cat_success(sprintf("✓ Base image already exists: %s\n", base_uri))
      return(base_uri)
    }
  }

  # Create temporary build directory
  build_dir <- tempfile(pattern = "starburst_base_build_")
  dir.create(build_dir, recursive = TRUE)
  on.exit(unlink(build_dir, recursive = TRUE), add = TRUE)

  tryCatch({
    # Process Dockerfile.base template
    dockerfile_template <- system.file("templates", "Dockerfile.base", package = "starburst")
    if (!file.exists(dockerfile_template)) {
      stop("Dockerfile.base template not found")
    }

    template_content <- readLines(dockerfile_template)
    dockerfile_content <- gsub("\\{\\{R_VERSION\\}\\}", r_version, template_content)
    writeLines(dockerfile_content, file.path(build_dir, "Dockerfile"))

    cat_info(sprintf("   • Build directory: %s\n", build_dir))
    cat_info(sprintf("   • R version: %s\n", r_version))
    cat_info("   • This includes system deps + renv + future/globals/qs/paws\n")
    cat_info("   • This is a one-time build (3-5 min), reused by all projects\n")

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

    # Docker login - use temp file to avoid exposing password in process list
    temp_pw_file <- tempfile(fileext = ".txt")
    on.exit(unlink(temp_pw_file), add = TRUE)
    writeLines(password, temp_pw_file)

    # Pass password via stdin from file (more secure than echo)
    login_cmd <- sprintf("docker login --username AWS --password-stdin %s < %s",
                        shQuote(token_data$proxyEndpoint), shQuote(temp_pw_file))
    login_result <- system(login_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)

    if (login_result != 0) {
      stop(sprintf("Failed to authenticate with ECR for account %s in region %s",
                  account_id, region))
    }

    # Build multi-platform base image
    ecr_uri <- sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker", account_id, region)
    image_tag <- sprintf("%s:%s", ecr_uri, base_tag)
    cat_info(sprintf("   • Building multi-platform base image: %s\n", image_tag))
    cat_info("   • Platforms: linux/amd64, linux/arm64\n")

    # Ensure buildx builder exists with docker-container driver (required for multi-platform)
    # Per Docker docs: use --bootstrap flag and set as default with --use
    buildx_setup_cmd <- "docker buildx create --name starburst-builder --driver docker-container --bootstrap --use 2>/dev/null || docker buildx use starburst-builder"
    system(buildx_setup_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)

    # Build and push multi-platform image (no cache for clean multi-platform build)
    # Use --builder flag to explicitly specify the builder (works from R's system())
    build_cmd <- sprintf("docker buildx build --builder starburst-builder --platform linux/amd64,linux/arm64 --no-cache -t %s --push %s",
                        shQuote(image_tag), shQuote(build_dir))
    build_result <- system(build_cmd)

    if (build_result != 0) {
      stop("Docker buildx build failed")
    }

    cat_success(sprintf("✓ Base image built and pushed: %s\n", image_tag))
    cat_success("✓ This base image will be reused by all future projects\n")

    return(image_tag)

  }, error = function(e) {
    cat_error(sprintf("✗ Base image build failed: %s\n", e$message))
    stop(e)
  })
}

#' Get base image source URI
#'
#' @param use_public Logical, use public ECR base image (default TRUE)
#' @keywords internal
get_base_image_source <- function(use_public = TRUE) {
  r_version <- paste0(R.version$major, ".", R.version$minor)

  if (use_public) {
    # Public ECR (no auth needed, instant pull)
    # NOTE: This will be available when public images are published
    return(sprintf("public.ecr.aws/starburst/base:r%s", r_version))
  } else {
    # Private ECR (build if missing)
    config <- get_starburst_config()
    account_id <- config$aws_account_id
    region <- config$region
    return(sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker:base-%s",
                   account_id, region, r_version))
  }
}

#' Ensure base image exists
#'
#' @param region AWS region
#' @param use_public Logical, use public ECR base image (default TRUE)
#' @keywords internal
ensure_base_image <- function(region, use_public = NULL) {
  # Get preference from config or default to FALSE (safer default)
  if (is.null(use_public)) {
    config <- get_starburst_config()
    use_public <- config$use_public_base %||% FALSE
  }

  r_version <- paste0(R.version$major, ".", R.version$minor)
  base_tag <- sprintf("base-%s", r_version)

  if (use_public) {
    # Try public base image first, fall back to private if not available
    base_uri <- get_base_image_source(use_public = TRUE)
    cat_info(sprintf("Trying public base image: %s\n", base_uri))

    # For now, public images aren't published yet, so fall back
    cat_warn("   Public base images not yet available\n")
    cat_info("   Falling back to private base image build...\n")
    use_public <- FALSE
  }

  if (!use_public) {
    # Use private base image (build if needed)
    if (!check_ecr_image_exists(base_tag, region)) {
      cat_info("📦 Base image not found in private ECR, building it now...\n")
      cat_info("   (This will take 3-5 minutes, but only needed once per R version)\n")
      build_base_image(region)
    } else {
      base_uri <- get_base_image_uri(region)
      cat_info(sprintf("✓ Using existing private base image: %s\n", base_uri))
    }

    return(get_base_image_uri(region))
  }
}

#' Build environment image
#'
#' @param tag Image tag
#' @param region AWS region
#' @param use_public Logical, use public ECR base image (default NULL = from config)
#' @keywords internal
build_environment_image <- function(tag, region, use_public = NULL) {
  cat_info("🐳 Building project Docker image...\n")

  # Validate Docker is installed
  docker_check <- system2("docker", "--version", stdout = TRUE, stderr = TRUE)
  if (attr(docker_check, "status") != 0 && !is.null(attr(docker_check, "status"))) {
    stop("Docker is not installed or not accessible. Please install Docker: https://docs.docker.com/get-docker/")
  }

  # Ensure base image exists (will build if needed, or use public)
  base_image_uri <- ensure_base_image(region, use_public = use_public)

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
    dockerfile_content <- gsub("\\{\\{BASE_IMAGE\\}\\}", base_image_uri, template_content)
    writeLines(dockerfile_content, file.path(build_dir, "Dockerfile"))

    cat_info(sprintf("   • Build directory: %s\n", build_dir))
    cat_info(sprintf("   • Base image: %s\n", base_image_uri))
    cat_info("   • Building only project-specific packages...\n")

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

    # Docker login - use temp file to avoid exposing password in process list
    temp_pw_file <- tempfile(fileext = ".txt")
    on.exit(unlink(temp_pw_file), add = TRUE)
    writeLines(password, temp_pw_file)

    # Pass password via stdin from file (more secure than echo)
    login_cmd <- sprintf("docker login --username AWS --password-stdin %s < %s",
                        shQuote(token_data$proxyEndpoint), shQuote(temp_pw_file))
    login_result <- system(login_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)

    if (login_result != 0) {
      stop(sprintf("Failed to authenticate with ECR for account %s in region %s",
                  account_id, region))
    }

    # Build multi-platform image
    image_tag <- sprintf("%s:%s", ecr_uri, tag)
    cat_info(sprintf("   • Building multi-platform image: %s\n", image_tag))
    cat_info("   • Platforms: linux/amd64, linux/arm64\n")

    # Ensure buildx builder exists with docker-container driver (required for multi-platform)
    # Per Docker docs: use --bootstrap flag and set as default with --use
    buildx_setup_cmd <- "docker buildx create --name starburst-builder --driver docker-container --bootstrap --use 2>/dev/null || docker buildx use starburst-builder"
    system(buildx_setup_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)

    # Build and push multi-platform image (no cache for clean multi-platform build)
    # Use --builder flag to explicitly specify the builder (works from R's system())
    build_cmd <- sprintf("docker buildx build --builder starburst-builder --platform linux/amd64,linux/arm64 --no-cache -t %s --push %s",
                        shQuote(image_tag), shQuote(build_dir))
    build_result <- system(build_cmd)

    if (build_result != 0) {
      stop("Docker buildx build failed")
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

        cat_success(sprintf("✓ Using existing task definition: %s\n", task_def$taskDefinitionArn))
        return(task_def$taskDefinitionArn)
      }
    }
  }, error = function(e) {
    # Continue to create new task definition
  })

  # Create new task definition
  cat_info("   • Registering new task definition...\n")
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
