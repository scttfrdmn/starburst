#' Setup staRburst
#'
#' One-time configuration to set up AWS resources for staRburst
#'
#' @param region AWS region (default: "us-east-1")
#' @param force Force re-setup even if already configured
#' @param use_public_base Use public base Docker images (default: TRUE).
#'   Set to FALSE to build private base images in your ECR.
#' @param ecr_image_ttl_days Number of days to keep Docker images in ECR (default: NULL = never delete).
#'   AWS will automatically delete images older than this many days.
#'   This prevents surprise costs if you stop using staRburst.
#'   Recommended: 30 days for regular users, 7 days for occasional users.
#'   When images are deleted, they will be rebuilt on next use (adds 3-5 min).
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Default: keep images forever (~$0.50/month idle cost)
#' starburst_setup()
#'
#' # Auto-delete images after 30 days (saves money if you stop using it)
#' starburst_setup(ecr_image_ttl_days = 30)
#'
#' # Use private base images with 7-day cleanup
#' starburst_setup(use_public_base = FALSE, ecr_image_ttl_days = 7)
#' }
starburst_setup <- function(region = "us-east-1", force = FALSE, use_public_base = TRUE, ecr_image_ttl_days = NULL) {

  cat_header("⚡ staRburst Setup\n")

  # Check if already set up
  if (!force && is_setup_complete()) {
    cat_info("[OK] staRburst is already configured\n")
    cat_info("  Use starburst_setup(force = TRUE) to reconfigure\n")
    return(invisible(TRUE))
  }

  cat_info("\nThis will configure AWS resources for staRburst:\n")
  cat_info("  • S3 bucket for data transfer\n")
  cat_info("  • ECR repository for Docker images\n")
  cat_info("  • ECS cluster for Fargate tasks\n")
  cat_info("  • VPC resources (subnets, security groups)\n")

  if (interactive()) {
    response <- readline("\nContinue? [y/n]: ")
    if (tolower(response) != "y") {
      cat_info("Setup cancelled\n")
      return(invisible(FALSE))
    }
  }

  # Step 1: AWS Credentials
  cat_info("\n[1/5] Checking AWS credentials...\n")
  if (!check_aws_credentials()) {
    cat_error("AWS credentials not found\n")
    cat_info("\nPlease configure AWS credentials using one of:\n")
    cat_info("  1. AWS CLI: aws configure\n")
    cat_info("  2. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY\n")
    cat_info("  3. AWS credentials file: ~/.aws/credentials\n")
    stop("AWS credentials required")
  }
  cat_success("[OK] AWS credentials valid\n")

  # Step 2: S3 Bucket
  cat_info("\n[2/5] Setting up S3 bucket...\n")
  bucket_name <- sprintf("starburst-%s-%s",
                        get_aws_account_id(),
                        substr(uuid::UUIDgenerate(), 1, 8))

  bucket <- create_starburst_bucket(bucket_name, region)
  cat_success(sprintf("[OK] S3 bucket created: %s\n", bucket))

  # Step 3: ECR Repository
  cat_info("\n[3/5] Setting up ECR repository...\n")
  repo <- create_ecr_repository("starburst-worker", region)
  cat_success(sprintf("[OK] ECR repository created: %s\n", repo$repositoryUri))

  # Set up ECR lifecycle policy for auto-cleanup
  if (!is.null(ecr_image_ttl_days)) {
    cat_info(sprintf("   • Setting ECR auto-cleanup policy (TTL: %d days)...\n", ecr_image_ttl_days))
    create_ecr_lifecycle_policy(region, "starburst-worker", ecr_image_ttl_days)
  } else {
    cat_info("   • ECR auto-cleanup disabled (images kept indefinitely)\n")
    cat_info("     Idle cost: ~$0.50/month for stored images\n")
    cat_info("     To enable: starburst_setup(ecr_image_ttl_days = 30)\n")
  }

  # Step 4: ECS Cluster
  cat_info("\n[4/5] Setting up ECS cluster...\n")
  cluster <- create_ecs_cluster("starburst-cluster", region)
  cat_success(sprintf("[OK] ECS cluster created: %s\n", cluster$clusterName))

  # Step 5: VPC Resources
  cat_info("\n[5/5] Setting up VPC resources...\n")
  vpc_resources <- setup_vpc_resources(region)
  cat_success("[OK] VPC resources created\n")

  # Get AWS account ID for config
  account_id <- get_aws_account_id()

  # Save configuration
  config <- list(
    region = region,
    bucket = bucket,
    ecr_repository = repo$repositoryUri,
    ecs_cluster = cluster$clusterName,
    cluster_name = cluster$clusterName,  # Add for EC2 compatibility
    vpc_id = vpc_resources$vpc_id,
    subnets = vpc_resources$subnets,
    security_groups = vpc_resources$security_groups,
    use_public_base = use_public_base,
    ecr_image_ttl_days = ecr_image_ttl_days,
    aws_account_id = account_id,
    setup_at = Sys.time()
  )

  save_config(config)

  # Check quotas proactively
  cat_info("\n📊 Checking Fargate quotas...\n")
  quota_info <- check_fargate_quota(region)

  cat_info(sprintf("Current Fargate vCPU quota: %d\n", quota_info$limit))
  cat_info(sprintf("  Allows ~%d workers with 4 vCPUs each\n",
                  floor(quota_info$limit / 4)))

  if (quota_info$limit < 500) {
    cat_warn("\n[TIP] For typical parallel workloads, we recommend 500+ vCPUs\n")

    if (!quota_info$increase_pending && interactive()) {
      response <- readline("\nRequest quota increase to 500 vCPUs now? [y/n]: ")
      if (tolower(response) == "y") {
        case_id <- request_quota_increase(
          service = "fargate",
          quota_code = "L-3032A538",
          desired_value = 500,
          region = region,
          reason = "staRburst parallel R computing setup"
        )

        if (!is.null(case_id)) {
          cat_success(sprintf("[OK] Quota increase requested (Case ID: %s)\n", case_id))
          cat_success("[OK] You'll receive email when approved (usually 1-24 hours)\n")
        }
      }
    }
  } else {
    cat_success(sprintf("[OK] Quota is sufficient (%d vCPUs)\n", quota_info$limit))
  }

  # Build initial environment
  cat_info("\n🔨 Building initial R environment...\n")
  cat_info("This may take 5-10 minutes on first run\n")

  env_hash <- build_initial_environment(region)
  cat_success("[OK] Environment built and cached\n")

  # Final message
  cat_success("\n✅ staRburst setup complete!\n")
  cat_info("\nQuick start:\n")
  cat_info("  library(furrr)\n")
  cat_info("  plan(future_starburst, workers = 50)\n")
  cat_info("  results <- future_map(data, expensive_function)\n")

  invisible(TRUE)
}

#' Get staRburst configuration
#'
#' @return List of configuration values
#' @keywords internal
get_starburst_config <- function() {
  config_file <- config_path()

  if (!file.exists(config_file)) {
    stop("staRburst not configured. Run starburst_setup() first.")
  }

  readRDS(config_file)
}

#' Save staRburst configuration
#'
#' @keywords internal
save_config <- function(config) {
  config_dir <- config_dir()
  if (!dir.exists(config_dir)) {
    dir.create(config_dir, recursive = TRUE)
  }

  config_file <- config_path()
  saveRDS(config, config_file)

  invisible(NULL)
}

#' Check if setup is complete
#'
#' @keywords internal
is_setup_complete <- function() {
  config_file <- config_path()
  file.exists(config_file)
}

#' Get configuration directory
#'
#' @keywords internal
config_dir <- function() {
  config_home <- Sys.getenv("XDG_CONFIG_HOME", "~/.config")
  file.path(config_home, "starburst")
}

#' Get configuration file path
#'
#' @keywords internal
config_path <- function() {
  file.path(config_dir(), "config.rds")
}

#' Configure staRburst options
#'
#' @param max_cost_per_job Maximum cost per job in dollars
#' @param cost_alert_threshold Cost threshold for alerts
#' @param auto_cleanup_s3 Automatically clean up S3 files after completion
#' @param ... Additional configuration options
#'
#' @export
#'
#' @examples
#' \dontrun{
#' starburst_config(
#'   max_cost_per_job = 10,
#'   cost_alert_threshold = 5
#' )
#' }
starburst_config <- function(max_cost_per_job = NULL,
                             cost_alert_threshold = NULL,
                             auto_cleanup_s3 = NULL,
                             ...) {

  config <- get_starburst_config()

  # Update config
  if (!is.null(max_cost_per_job)) {
    config$max_cost_per_job <- max_cost_per_job
  }

  if (!is.null(cost_alert_threshold)) {
    config$cost_alert_threshold <- cost_alert_threshold
  }

  if (!is.null(auto_cleanup_s3)) {
    config$auto_cleanup_s3 <- auto_cleanup_s3
  }

  # Handle additional options
  extra_opts <- list(...)
  if (length(extra_opts) > 0) {
    config <- c(config, extra_opts)
  }

  save_config(config)

  cat_success("[OK] Configuration updated\n")

  invisible(config)
}

#' Show staRburst status
#'
#' @export
starburst_status <- function() {
  config <- get_starburst_config()

  cat_header("staRburst Status\n")
  cat_info(sprintf("Region: %s\n", config$region))
  cat_info(sprintf("S3 Bucket: %s\n", config$bucket))
  cat_info(sprintf("ECR Repository: %s\n", config$ecr_repository))

  # Check quota
  quota_info <- check_fargate_quota(config$region)
  cat_info(sprintf("\nFargate vCPU Quota: %d / %d used\n",
                  quota_info$used, quota_info$limit))

  # List running clusters
  cat_info("\nActive Clusters:\n")
  clusters <- list_active_clusters(config$region)

  if (length(clusters) == 0) {
    cat_info("  (none)\n")
  } else {
    for (cluster in clusters) {
      cat_info(sprintf("  • %s: %d tasks running\n",
                      cluster$id, cluster$task_count))
    }
  }

  invisible(NULL)
}

#' Create S3 bucket for staRburst
#'
#' @keywords internal
create_starburst_bucket <- function(bucket_name, region) {
  s3 <- get_s3_client(region)

  # Check if bucket already exists
  bucket_exists <- tryCatch({
    s3$head_bucket(Bucket = bucket_name)
    TRUE
  }, error = function(e) {
    FALSE
  })

  if (bucket_exists) {
    cat_info(sprintf("   • Bucket already exists: %s\n", bucket_name))
    return(bucket_name)
  }

  # Create bucket
  tryCatch({
    if (region == "us-east-1") {
      s3$create_bucket(Bucket = bucket_name)
    } else {
      s3$create_bucket(
        Bucket = bucket_name,
        CreateBucketConfiguration = list(
          LocationConstraint = region
        )
      )
    }

    # Enable encryption
    tryCatch({
      s3$put_bucket_encryption(
        Bucket = bucket_name,
        ServerSideEncryptionConfiguration = list(
          Rules = list(
            list(
              ApplyServerSideEncryptionByDefault = list(
                SSEAlgorithm = "AES256"
              )
            )
          )
        )
      )
    }, error = function(e) {
      cat_warn(sprintf("[WARNING] Could not enable bucket encryption: %s\n", e$message))
    })

    # Set lifecycle policy (delete after 7 days)
    tryCatch({
      s3$put_bucket_lifecycle_configuration(
        Bucket = bucket_name,
        LifecycleConfiguration = list(
          Rules = list(
            list(
              ID = "cleanup-old-files",
              Status = "Enabled",
              Expiration = list(Days = as.integer(7)),
              Filter = list()
            )
          )
        )
      )
    }, error = function(e) {
      cat_warn(sprintf("[WARNING] Could not set lifecycle policy: %s\n", e$message))
    })

    bucket_name

  }, error = function(e) {
    stop(sprintf("Failed to create S3 bucket: %s", e$message))
  })
}

#' Create ECR repository
#'
#' @keywords internal
create_ecr_repository <- function(repo_name, region) {
  ecr <- get_ecr_client(region)

  tryCatch({
    response <- with_ecr_retry(
      {
        ecr$create_repository(
          repositoryName = repo_name,
          imageTagMutability = "MUTABLE",
          imageScanningConfiguration = list(
            scanOnPush = TRUE
          )
        )
      },
      max_attempts = 3,
      operation_name = "ECR CreateRepository"
    )

    response$repository

  }, error = function(e) {
    if (grepl("RepositoryAlreadyExistsException", e$message)) {
      # Repository exists, describe it
      response <- ecr$describe_repositories(
        repositoryNames = list(repo_name)
      )
      return(response$repositories[[1]])
    }
    stop(sprintf("Failed to create ECR repository: %s", e$message))
  })
}

#' Create ECS cluster
#'
#' @keywords internal
create_ecs_cluster <- function(cluster_name, region) {
  ecs <- get_ecs_client(region)

  # Check if cluster already exists
  cluster_exists <- tryCatch({
    response <- ecs$describe_clusters(clusters = list(cluster_name))
    length(response$clusters) > 0 && response$clusters[[1]]$status == "ACTIVE"
  }, error = function(e) {
    FALSE
  })

  if (cluster_exists) {
    cat_info(sprintf("   • Cluster already exists: %s\n", cluster_name))
    response <- ecs$describe_clusters(clusters = list(cluster_name))
    return(response$clusters[[1]])
  }

  tryCatch({
    response <- ecs$create_cluster(
      clusterName = cluster_name,
      capacityProviders = list("FARGATE", "FARGATE_SPOT"),
      defaultCapacityProviderStrategy = list(
        list(
          capacityProvider = "FARGATE",
          weight = 1,
          base = 0
        )
      )
    )

    response$cluster

  }, error = function(e) {
    stop(sprintf("Failed to create ECS cluster: %s", e$message))
  })
}

#' Setup VPC resources
#'
#' @keywords internal
setup_vpc_resources <- function(region) {
  ec2 <- get_ec2_client(region)

  # Use default VPC if exists, otherwise create
  vpcs <- ec2$describe_vpcs(Filters = list(
    list(Name = "isDefault", Values = list("true"))
  ))

  if (length(vpcs$Vpcs) > 0) {
    vpc_id <- vpcs$Vpcs[[1]]$VpcId
  } else {
    # Create VPC (simplified - production would be more complex)
    vpc <- ec2$create_vpc(CidrBlock = "10.0.0.0/16")
    vpc_id <- vpc$Vpc$VpcId
  }

  # Get or create private subnets
  subnets <- get_or_create_subnets(vpc_id, region)

  # Get or create security group
  security_group <- get_or_create_security_group(vpc_id, region)

  list(
    vpc_id = vpc_id,
    subnets = subnets,
    security_groups = list(security_group)
  )
}

# Output helpers

cat_header <- function(...) {
  cat("\n", crayon::bold(...), "\n", sep = "")
}

cat_info <- function(...) {
  cat(crayon::blue(...))
}

cat_success <- function(...) {
  cat(crayon::green(...))
}

cat_warn <- function(...) {
  cat(crayon::yellow(...))
}

cat_error <- function(...) {
  cat(crayon::red(...))
}

#' Setup EC2 capacity providers for staRburst
#'
#' One-time setup for EC2 launch type. Creates IAM roles, instance profiles,
#' and capacity providers for specified instance types.
#'
#' @param region AWS region (default: "us-east-1")
#' @param instance_types Character vector of instance types to setup (default: c("c7g.xlarge", "c7i.xlarge"))
#' @param force Force re-setup even if already configured
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Setup with default instance types (Graviton and Intel)
#' starburst_setup_ec2()
#'
#' # Setup with custom instance types
#' starburst_setup_ec2(instance_types = c("c7g.2xlarge", "r7g.xlarge"))
#' }
starburst_setup_ec2 <- function(region = "us-east-1",
                                instance_types = c("c7g.xlarge", "c7i.xlarge"),
                                force = FALSE) {

  cat_header("⚡ staRburst EC2 Setup\n")

  # First ensure basic setup is complete
  if (!is_setup_complete()) {
    cat_error("[ERROR] Basic staRburst setup not complete\n")
    cat_info("  Run starburst_setup() first\n")
    return(invisible(FALSE))
  }

  # Check AWS credentials
  if (!check_aws_credentials()) {
    cat_error("[ERROR] AWS credentials not found\n")
    return(invisible(FALSE))
  }

  cat_info("\nThis will configure EC2 resources for staRburst:\n")
  cat_info("  • IAM instance role and profile\n")
  cat_info("  • Security groups for ECS workers\n")
  cat_info(sprintf("  • Capacity providers for %d instance types\n", length(instance_types)))
  cat_info(sprintf("  • Instance types: %s\n", paste(instance_types, collapse = ", ")))

  if (interactive() && !force) {
    response <- readline("\nContinue? [y/n]: ")
    if (tolower(response) != "y") {
      cat_info("Setup cancelled\n")
      return(invisible(FALSE))
    }
  }

  # Get configuration
  config <- get_starburst_config()

  # Create backend-like object for each instance type
  cat_info("\n[1/2] Setting up IAM roles and security groups...\n")

  # This will be called once per instance type, but the functions are idempotent
  ensure_ecs_instance_profile(region)
  ensure_ecs_security_group(region)

  cat_success("[OK] IAM roles and security groups ready\n")

  # Setup capacity providers for each instance type
  cat_info(sprintf("\n[2/2] Setting up capacity providers for %d instance types...\n", length(instance_types)))

  for (instance_type in instance_types) {
    cat_info(sprintf("\n  Setting up %s...\n", instance_type))

    architecture <- get_architecture_from_instance_type(instance_type)

    # Create mock backend for setup
    backend <- list(
      region = region,
      cluster = config$cluster %||% "starburst-cluster",
      instance_type = instance_type,
      architecture = architecture,
      use_spot = FALSE,  # Default to on-demand for setup
      capacity_provider_name = sprintf("starburst-%s", gsub("\\.", "-", instance_type)),
      asg_name = sprintf("starburst-asg-%s", gsub("\\.", "-", instance_type)),
      aws_account_id = config$aws_account_id
    )

    tryCatch({
      setup_ec2_capacity_provider(backend)
      cat_success(sprintf("  [OK] %s ready\n", instance_type))
    }, error = function(e) {
      cat_error(sprintf("  [ERROR] Failed to setup %s: %s\n", instance_type, e$message))
    })
  }

  cat_success("\n[OK] EC2 setup complete!\n")
  cat_info("\nYou can now use EC2 launch type:\n")
  cat_info("  plan(starburst, workers = 100, launch_type = \"EC2\",\n")
  cat_info("       instance_type = \"c7g.xlarge\", use_spot = TRUE)\n")

  invisible(TRUE)
}

#' Clean up staRburst ECR images
#'
#' Manually delete Docker images from ECR to save storage costs.
#' Images will be rebuilt on next use (adds 3-5 min delay).
#'
#' @param force Delete all images immediately, ignoring TTL
#' @param region AWS region (default: from config)
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Delete images past TTL
#' starburst_cleanup_ecr()
#'
#' # Delete all images immediately (save $0.50/month)
#' starburst_cleanup_ecr(force = TRUE)
#' }
starburst_cleanup_ecr <- function(force = FALSE, region = NULL) {
  if (!is_setup_complete()) {
    cat_error("[ERROR] staRburst not configured. Run starburst_setup() first.\n")
    return(invisible(FALSE))
  }

  config <- get_starburst_config()
  if (is.null(region)) {
    region <- config$region
  }

  ecr <- get_ecr_client(region)
  repo_name <- "starburst-worker"

  cat_header("[Cleaning] staRburst ECR Cleanup\n")

  # List all images
  tryCatch({
    images <- ecr$list_images(repositoryName = repo_name)

    if (length(images$imageIds) == 0) {
      cat_info("[OK] No images to clean up\n")
      return(invisible(TRUE))
    }

    cat_info(sprintf("Found %d images in ECR\n", length(images$imageIds)))

    # Get detailed info for each image
    image_details <- ecr$describe_images(repositoryName = repo_name)$imageDetails

    images_to_delete <- list()

    for (img in image_details) {
      image_tag <- if (length(img$imageTags) > 0) img$imageTags[[1]] else "untagged"
      push_time <- img$imagePushedAt
      age_days <- as.numeric(difftime(Sys.time(), push_time, units = "days"))
      size_mb <- img$imageSizeInBytes / 1024 / 1024

      if (force) {
        cat_info(sprintf("  • %s (%.0f days old, %.1f MB) - WILL DELETE\n",
                        image_tag, age_days, size_mb))
        images_to_delete <- c(images_to_delete, list(list(imageTag = image_tag)))
      } else if (!is.null(config$ecr_image_ttl_days) && age_days > config$ecr_image_ttl_days) {
        cat_info(sprintf("  • %s (%.0f days old, %.1f MB) - EXPIRED\n",
                        image_tag, age_days, size_mb))
        images_to_delete <- c(images_to_delete, list(list(imageTag = image_tag)))
      } else {
        cat_info(sprintf("  • %s (%.0f days old, %.1f MB) - keeping\n",
                        image_tag, age_days, size_mb))
      }
    }

    if (length(images_to_delete) == 0) {
      cat_success("\n[OK] No images need cleanup\n")
      return(invisible(TRUE))
    }

    # Confirm deletion
    if (interactive() && !force) {
      response <- readline(sprintf("\nDelete %d images? [y/n]: ", length(images_to_delete)))
      if (tolower(response) != "y") {
        cat_info("Cleanup cancelled\n")
        return(invisible(FALSE))
      }
    }

    # Delete images
    cat_info(sprintf("\nDeleting %d images...\n", length(images_to_delete)))
    ecr$batch_delete_image(
      repositoryName = repo_name,
      imageIds = images_to_delete
    )

    cat_success(sprintf("[OK] Deleted %d images\n", length(images_to_delete)))
    cat_info("  Images will be rebuilt on next use (adds 3-5 min)\n")

    invisible(TRUE)

  }, error = function(e) {
    cat_error(sprintf("[ERROR] Cleanup failed: %s\n", e$message))
    invisible(FALSE)
  })
}
