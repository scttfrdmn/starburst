#' Setup staRburst
#'
#' One-time configuration to set up AWS resources for staRburst
#'
#' @param region AWS region (default: "us-east-1")
#' @param force Force re-setup even if already configured
#' @param use_public_base Use public base Docker images (default: TRUE).
#'   Set to FALSE to build private base images in your ECR.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Default: use public base images (faster setup)
#' starburst_setup()
#'
#' # Use private base images
#' starburst_setup(use_public_base = FALSE)
#' }
starburst_setup <- function(region = "us-east-1", force = FALSE, use_public_base = TRUE) {
  
  cat_header("⚡ staRburst Setup\n")
  
  # Check if already set up
  if (!force && is_setup_complete()) {
    cat_info("✓ staRburst is already configured\n")
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
  cat_success("✓ AWS credentials valid\n")
  
  # Step 2: S3 Bucket
  cat_info("\n[2/5] Setting up S3 bucket...\n")
  bucket_name <- sprintf("starburst-%s-%s", 
                        get_aws_account_id(), 
                        substr(uuid::UUIDgenerate(), 1, 8))
  
  bucket <- create_starburst_bucket(bucket_name, region)
  cat_success(sprintf("✓ S3 bucket created: %s\n", bucket))
  
  # Step 3: ECR Repository
  cat_info("\n[3/5] Setting up ECR repository...\n")
  repo <- create_ecr_repository("starburst-worker", region)
  cat_success(sprintf("✓ ECR repository created: %s\n", repo$repositoryUri))
  
  # Step 4: ECS Cluster
  cat_info("\n[4/5] Setting up ECS cluster...\n")
  cluster <- create_ecs_cluster("starburst-cluster", region)
  cat_success(sprintf("✓ ECS cluster created: %s\n", cluster$clusterName))
  
  # Step 5: VPC Resources
  cat_info("\n[5/5] Setting up VPC resources...\n")
  vpc_resources <- setup_vpc_resources(region)
  cat_success("✓ VPC resources created\n")
  
  # Save configuration
  config <- list(
    region = region,
    bucket = bucket,
    ecr_repository = repo$repositoryUri,
    ecs_cluster = cluster$clusterName,
    vpc_id = vpc_resources$vpc_id,
    subnets = vpc_resources$subnets,
    security_groups = vpc_resources$security_groups,
    use_public_base = use_public_base,
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
    cat_warn("\n💡 For typical parallel workloads, we recommend 500+ vCPUs\n")
    
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
          cat_success(sprintf("✓ Quota increase requested (Case ID: %s)\n", case_id))
          cat_success("✓ You'll receive email when approved (usually 1-24 hours)\n")
        }
      }
    }
  } else {
    cat_success(sprintf("✓ Quota is sufficient (%d vCPUs)\n", quota_info$limit))
  }
  
  # Build initial environment
  cat_info("\n🔨 Building initial R environment...\n")
  cat_info("This may take 5-10 minutes on first run\n")
  
  env_hash <- build_initial_environment(region)
  cat_success("✓ Environment built and cached\n")
  
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
  
  cat_success("✓ Configuration updated\n")
  
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
    
    # Set lifecycle policy (delete after 7 days)
    s3$put_bucket_lifecycle_configuration(
      Bucket = bucket_name,
      LifecycleConfiguration = list(
        Rules = list(
          list(
            Id = "cleanup-old-files",
            Status = "Enabled",
            Expiration = list(Days = 7),
            Filter = list(Prefix = "")
          )
        )
      )
    )
    
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
    response <- ecr$create_repository(
      repositoryName = repo_name,
      imageTagMutability = "MUTABLE",
      imageScanningConfiguration = list(
        scanOnPush = TRUE
      )
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
