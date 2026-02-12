#' EC2 Pool Management for staRburst
#'
#' Functions for managing Auto-Scaling Groups and ECS Capacity Providers
#' to maintain warm pools of EC2 instances for fast task execution.
#'
#' @name ec2-pool
#' @keywords internal
NULL

#' Get EC2 client
#'
#' @param region AWS region
#' @return EC2 client
#' @keywords internal
get_ec2_client <- function(region) {
  paws.compute::ec2(config = list(region = region))
}

#' Get Auto Scaling client
#'
#' @param region AWS region
#' @return Auto Scaling client
#' @keywords internal
get_autoscaling_client <- function(region) {
  paws.management::autoscaling(config = list(region = region))
}

#' Get ECS-optimized AMI ID for region and architecture
#'
#' @param region AWS region
#' @param architecture CPU architecture ("X86_64" or "ARM64")
#' @return AMI ID
#' @keywords internal
get_ecs_optimized_ami <- function(region, architecture = "X86_64") {
  ssm <- paws.management::ssm(config = list(region = region))

  # AWS SSM parameter paths for ECS-optimized AMIs
  param_path <- if (architecture == "ARM64") {
    "/aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id"
  } else {
    "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
  }

  tryCatch({
    result <- ssm$get_parameter(Name = param_path)
    result$Parameter$Value
  }, error = function(e) {
    stop(sprintf("Failed to get ECS-optimized AMI for %s in %s: %s",
                 architecture, region, e$message))
  })
}

#' Setup EC2 capacity provider for ECS cluster
#'
#' Creates Launch Template, Auto-Scaling Group, and ECS Capacity Provider
#'
#' @param backend Backend configuration object
#' @return List with capacity provider details
#' @keywords internal
setup_ec2_capacity_provider <- function(backend) {
  cat_info(sprintf("🔧 Setting up EC2 capacity provider for %s...\n", backend$instance_type))

  region <- backend$region
  cluster_name <- backend$cluster
  instance_type <- backend$instance_type
  architecture <- backend$architecture
  use_spot <- backend$use_spot
  capacity_provider_name <- backend$capacity_provider_name
  asg_name <- backend$asg_name

  ec2 <- get_ec2_client(region)
  autoscaling <- get_autoscaling_client(region)
  ecs <- get_ecs_client(region)

  # Check if capacity provider already exists
  tryCatch({
    cp_response <- ecs$describe_capacity_providers(
      capacityProviders = list(capacity_provider_name)
    )
    if (length(cp_response$capacityProviders) > 0) {
      cat_success(sprintf("✓ Capacity provider already exists: %s\n", capacity_provider_name))
      return(invisible(NULL))
    }
  }, error = function(e) {
    # Capacity provider doesn't exist, continue with setup
  })

  # Get ECS-optimized AMI
  cat_info(sprintf("   • Finding ECS-optimized AMI for %s...\n", architecture))
  ami_id <- get_ecs_optimized_ami(region, architecture)
  cat_info(sprintf("   • AMI ID: %s\n", ami_id))

  # Get or create IAM instance profile
  instance_profile_arn <- ensure_ecs_instance_profile(region)

  # Get or create security group
  security_group_id <- ensure_ecs_security_group(region)

  # Create Launch Template
  lt_name <- sprintf("starburst-lt-%s", instance_type)
  cat_info(sprintf("   • Creating Launch Template: %s...\n", lt_name))

  user_data <- sprintf("#!/bin/bash\necho ECS_CLUSTER=%s >> /etc/ecs/ecs.config\necho ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config\necho ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config",
                       cluster_name)
  user_data_encoded <- as.character(base64enc::base64encode(charToRaw(user_data)))

  # Delete existing launch template if it exists
  tryCatch({
    ec2$delete_launch_template(LaunchTemplateName = lt_name)
  }, error = function(e) {
    # Launch template doesn't exist, continue
  })

  lt_params <- list(
    LaunchTemplateName = lt_name,
    LaunchTemplateData = list(
      ImageId = ami_id,
      InstanceType = instance_type,
      IamInstanceProfile = list(Arn = instance_profile_arn),
      SecurityGroupIds = list(security_group_id),
      UserData = user_data_encoded,
      TagSpecifications = list(
        list(
          ResourceType = "instance",
          Tags = list(
            list(Key = "Name", Value = sprintf("starburst-worker-%s", instance_type)),
            list(Key = "ManagedBy", Value = "starburst")
          )
        )
      )
    )
  )

  if (use_spot) {
    lt_params$LaunchTemplateData$InstanceMarketOptions <- list(
      MarketType = "spot",
      SpotOptions = list(
        MaxPrice = "", # Use on-demand price as max
        SpotInstanceType = "one-time"
      )
    )
  }

  tryCatch({
    lt_response <- do.call(ec2$create_launch_template, lt_params)
    cat_success(sprintf("✓ Launch Template created: %s\n", lt_name))
  }, error = function(e) {
    cat_error(sprintf("✗ Launch Template creation failed: %s\n", e$message))
    cat_error(sprintf("  Full error: %s\n", paste(capture.output(print(e)), collapse = "\n")))
    stop(e)
  })

  # Create Auto-Scaling Group
  cat_info(sprintf("   • Creating Auto-Scaling Group: %s...\n", asg_name))

  # Get default VPC subnets
  vpc_response <- ec2$describe_vpcs(Filters = list(list(Name = "isDefault", Values = list("true"))))
  if (length(vpc_response$Vpcs) == 0) {
    stop("No default VPC found. Please create a VPC first.")
  }
  vpc_id <- vpc_response$Vpcs[[1]]$VpcId

  subnet_response <- ec2$describe_subnets(Filters = list(list(Name = "vpc-id", Values = list(vpc_id))))
  subnet_ids <- sapply(subnet_response$Subnets, function(s) s$SubnetId)

  if (length(subnet_ids) == 0) {
    stop("No subnets found in default VPC")
  }

  # Delete existing ASG if it exists and wait for deletion to complete
  tryCatch({
    autoscaling$delete_auto_scaling_group(
      AutoScalingGroupName = asg_name,
      ForceDelete = TRUE
    )
    cat_info("   • Waiting for ASG deletion to complete...\n")

    # Wait for deletion (max 60 seconds)
    for (i in 1:12) {
      Sys.sleep(5)
      asg_exists <- tryCatch({
        autoscaling$describe_auto_scaling_groups(
          AutoScalingGroupNames = list(asg_name)
        )
        TRUE
      }, error = function(e) {
        FALSE
      })

      if (!asg_exists) {
        break
      }

      if (i == 12) {
        cat_warning("⚠ ASG deletion taking longer than expected, continuing anyway...\n")
      }
    }
  }, error = function(e) {
    # ASG doesn't exist, continue
  })

  asg_params <- list(
    AutoScalingGroupName = asg_name,
    MinSize = 0,
    MaxSize = 100,
    DesiredCapacity = 0,
    VPCZoneIdentifier = paste(subnet_ids, collapse = ","),
    LaunchTemplate = list(
      LaunchTemplateName = lt_name,
      Version = "$Latest"
    ),
    HealthCheckType = "EC2",
    HealthCheckGracePeriod = 300,
    Tags = list(
      list(
        Key = "Name",
        Value = sprintf("starburst-asg-%s", instance_type),
        PropagateAtLaunch = TRUE
      ),
      list(
        Key = "AmazonECSManaged",
        Value = "true",
        PropagateAtLaunch = FALSE
      )
    )
  )

  tryCatch({
    do.call(autoscaling$create_auto_scaling_group, asg_params)
    cat_success(sprintf("✓ Auto-Scaling Group created: %s\n", asg_name))
  }, error = function(e) {
    cat_error(sprintf("✗ ASG creation failed: %s\n", e$message))
    cat_error(sprintf("  Full error: %s\n", paste(capture.output(print(e)), collapse = "\n")))
    stop(e)
  })

  # Get the actual ASG ARN
  asg_describe <- autoscaling$describe_auto_scaling_groups(
    AutoScalingGroupNames = list(asg_name)
  )
  asg_arn <- asg_describe$AutoScalingGroups[[1]]$AutoScalingGroupARN

  # Create ECS Capacity Provider
  cat_info(sprintf("   • Creating ECS Capacity Provider: %s...\n", capacity_provider_name))

  cp_params <- list(
    name = capacity_provider_name,
    autoScalingGroupProvider = list(
      autoScalingGroupArn = asg_arn,
      managedScaling = list(
        status = "ENABLED",
        targetCapacity = 100,
        minimumScalingStepSize = 1,
        maximumScalingStepSize = 10
      ),
      managedTerminationProtection = "DISABLED"
    ),
    tags = list(
      list(key = "ManagedBy", value = "starburst")
    )
  )

  tryCatch({
    do.call(ecs$create_capacity_provider, cp_params)
    cat_success(sprintf("✓ Capacity Provider created: %s\n", capacity_provider_name))
  }, error = function(e) {
    cat_error(sprintf("✗ Capacity Provider creation failed: %s\n", e$message))
    stop(e)
  })

  # Ensure cluster exists
  cluster_exists <- tryCatch({
    cluster_response <- ecs$describe_clusters(clusters = list(cluster_name))
    length(cluster_response$clusters) > 0 && cluster_response$clusters[[1]]$status == "ACTIVE"
  }, error = function(e) {
    FALSE
  })

  if (!cluster_exists) {
    cat_info(sprintf("   • Creating ECS cluster: %s...\n", cluster_name))
    ecs$create_cluster(clusterName = cluster_name)
    cat_success(sprintf("✓ Cluster created: %s\n", cluster_name))
  }

  # Associate capacity provider with cluster
  cat_info(sprintf("   • Associating with cluster: %s...\n", cluster_name))

  # Get existing capacity providers
  cluster_response <- ecs$describe_clusters(clusters = list(cluster_name))
  existing_providers <- if (length(cluster_response$clusters) > 0) {
    cluster_response$clusters[[1]]$capacityProviders
  } else {
    list()
  }

  # Add new capacity provider if not already present
  if (!capacity_provider_name %in% existing_providers) {
    all_providers <- c(existing_providers, list(capacity_provider_name))

    ecs$put_cluster_capacity_providers(
      cluster = cluster_name,
      capacityProviders = all_providers,
      defaultCapacityProviderStrategy = list()
    )
    cat_success(sprintf("✓ Capacity Provider associated with cluster\n"))
  } else {
    cat_success(sprintf("✓ Capacity Provider already associated with cluster\n"))
  }

  cat_success("✓ EC2 capacity provider setup complete\n")

  invisible(list(
    capacity_provider_name = capacity_provider_name,
    asg_name = asg_name,
    launch_template_name = lt_name
  ))
}

#' Start warm EC2 pool
#'
#' Scales Auto-Scaling Group to desired capacity and waits for instances
#'
#' @param backend Backend configuration object
#' @param capacity Desired number of instances
#' @param timeout_seconds Maximum time to wait for instances (default: 180)
#' @return Invisible NULL
#' @keywords internal
start_warm_pool <- function(backend, capacity, timeout_seconds = 180) {
  cat_info(sprintf("🚀 Starting warm pool: %d instances of %s...\n", capacity, backend$instance_type))

  region <- backend$region
  cluster_name <- backend$cluster_name
  asg_name <- backend$asg_name

  autoscaling <- get_autoscaling_client(region)
  ecs <- get_ecs_client(region)

  # Scale ASG to desired capacity
  autoscaling$set_desired_capacity(
    AutoScalingGroupName = asg_name,
    DesiredCapacity = as.integer(capacity)
  )

  cat_info(sprintf("   • Waiting for instances to join cluster (timeout: %ds)...\n", timeout_seconds))

  start_time <- Sys.time()
  while (TRUE) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

    if (elapsed > timeout_seconds) {
      stop(sprintf("Timeout waiting for instances to join cluster after %d seconds", timeout_seconds))
    }

    # Check ASG status
    asg_response <- autoscaling$describe_auto_scaling_groups(
      AutoScalingGroupNames = list(asg_name)
    )

    if (length(asg_response$AutoScalingGroups) > 0) {
      asg <- asg_response$AutoScalingGroups[[1]]

      # Count in-service instances
      in_service <- 0
      if (length(asg$Instances) > 0) {
        in_service <- sum(sapply(asg$Instances, function(i) {
          if (!is.null(i$LifecycleState)) {
            i$LifecycleState == "InService"
          } else {
            FALSE
          }
        }))
      }

      cat_info(sprintf("   • Instances in service: %d/%d (%.0fs elapsed)\n",
                      in_service, capacity, elapsed))

      if (in_service >= capacity) {
        # Verify instances registered with ECS
        container_instances <- ecs$list_container_instances(cluster = cluster_name)

        if (length(container_instances$containerInstanceArns) >= capacity) {
          cat_success(sprintf("✓ Pool ready: %d instances available\n", in_service))
          return(invisible(NULL))
        }
      }
    }

    Sys.sleep(5)
  }
}

#' Stop warm pool
#'
#' Scales Auto-Scaling Group to zero
#'
#' @param backend Backend configuration object
#' @return Invisible NULL
#' @keywords internal
stop_warm_pool <- function(backend) {
  cat_info(sprintf("🛑 Stopping warm pool: %s...\n", backend$asg_name))

  region <- backend$region
  asg_name <- backend$asg_name

  autoscaling <- get_autoscaling_client(region)

  autoscaling$set_desired_capacity(
    AutoScalingGroupName = asg_name,
    DesiredCapacity = 0
  )

  cat_success("✓ Pool scaled to zero\n")

  invisible(NULL)
}

#' Get pool status
#'
#' Query current state of the EC2 pool
#'
#' @param backend Backend configuration object
#' @return List with pool status information
#' @keywords internal
get_pool_status <- function(backend) {
  region <- backend$region
  cluster_name <- backend$cluster_name
  asg_name <- backend$asg_name

  autoscaling <- get_autoscaling_client(region)
  ecs <- get_ecs_client(region)

  # Get ASG status
  asg_response <- autoscaling$describe_auto_scaling_groups(
    AutoScalingGroupNames = list(asg_name)
  )

  if (length(asg_response$AutoScalingGroups) == 0) {
    return(list(
      exists = FALSE,
      running_instances = 0,
      in_service_instances = 0,
      desired_capacity = 0,
      ecs_instances = 0
    ))
  }

  asg <- asg_response$AutoScalingGroups[[1]]

  # Count in-service instances
  in_service <- 0
  if (length(asg$Instances) > 0) {
    in_service <- sum(sapply(asg$Instances, function(i) {
      if (!is.null(i$LifecycleState)) {
        i$LifecycleState == "InService"
      } else {
        FALSE
      }
    }))
  }

  # Get ECS container instances
  container_instances <- ecs$list_container_instances(cluster = cluster_name)
  ecs_count <- length(container_instances$containerInstanceArns)

  list(
    exists = TRUE,
    running_instances = length(asg$Instances),
    in_service_instances = in_service,
    desired_capacity = asg$DesiredCapacity,
    ecs_instances = ecs_count,
    min_size = asg$MinSize,
    max_size = asg$MaxSize
  )
}

#' Ensure ECS instance IAM profile exists
#'
#' @param region AWS region
#' @return Instance profile ARN
#' @keywords internal
ensure_ecs_instance_profile <- function(region) {
  iam <- paws.security.identity::iam()

  role_name <- "starburstECSInstanceRole"
  profile_name <- "starburstECSInstanceProfile"

  # Check if role exists
  role_arn <- tryCatch({
    role_response <- iam$get_role(RoleName = role_name)
    role_response$Role$Arn
  }, error = function(e) {
    # Create role
    cat_info(sprintf("   • Creating IAM role: %s...\n", role_name))

    trust_policy <- jsonlite::toJSON(list(
      Version = "2012-10-17",
      Statement = list(
        list(
          Effect = "Allow",
          Principal = list(Service = "ec2.amazonaws.com"),
          Action = "sts:AssumeRole"
        )
      )
    ), auto_unbox = TRUE)

    role_response <- iam$create_role(
      RoleName = role_name,
      AssumeRolePolicyDocument = trust_policy,
      Description = "IAM role for staRburst ECS EC2 instances"
    )

    # Attach AWS managed policy for ECS
    iam$attach_role_policy(
      RoleName = role_name,
      PolicyArn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    )

    # Attach S3 access policy
    s3_policy <- jsonlite::toJSON(list(
      Version = "2012-10-17",
      Statement = list(
        list(
          Effect = "Allow",
          Action = list("s3:GetObject", "s3:PutObject", "s3:ListBucket"),
          Resource = list("arn:aws:s3:::starburst-results-*/*", "arn:aws:s3:::starburst-results-*")
        ),
        list(
          Effect = "Allow",
          Action = list("logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"),
          Resource = "arn:aws:logs:*:*:*"
        )
      )
    ), auto_unbox = TRUE)

    iam$put_role_policy(
      RoleName = role_name,
      PolicyName = "starburstS3Access",
      PolicyDocument = s3_policy
    )

    cat_success(sprintf("✓ IAM role created: %s\n", role_name))
    role_response$Role$Arn
  })

  # Check if instance profile exists
  profile_arn <- tryCatch({
    profile_response <- iam$get_instance_profile(InstanceProfileName = profile_name)
    profile_response$InstanceProfile$Arn
  }, error = function(e) {
    # Create instance profile
    cat_info(sprintf("   • Creating instance profile: %s...\n", profile_name))

    profile_response <- iam$create_instance_profile(
      InstanceProfileName = profile_name
    )

    # Add role to instance profile
    iam$add_role_to_instance_profile(
      InstanceProfileName = profile_name,
      RoleName = role_name
    )

    # Wait for profile to propagate
    Sys.sleep(10)

    cat_success(sprintf("✓ Instance profile created: %s\n", profile_name))
    profile_response$InstanceProfile$Arn
  })

  profile_arn
}

#' Ensure ECS security group exists
#'
#' @param region AWS region
#' @return Security group ID
#' @keywords internal
ensure_ecs_security_group <- function(region) {
  ec2 <- get_ec2_client(region)

  sg_name <- "starburst-ecs-workers"

  # Get default VPC
  vpc_response <- ec2$describe_vpcs(Filters = list(list(Name = "isDefault", Values = list("true"))))
  if (length(vpc_response$Vpcs) == 0) {
    stop("No default VPC found")
  }
  vpc_id <- vpc_response$Vpcs[[1]]$VpcId

  # Check if security group exists
  sg_response <- tryCatch({
    ec2$describe_security_groups(
      Filters = list(
        list(Name = "group-name", Values = list(sg_name)),
        list(Name = "vpc-id", Values = list(vpc_id))
      )
    )
  }, error = function(e) {
    list(SecurityGroups = list())
  })

  if (length(sg_response$SecurityGroups) > 0) {
    return(sg_response$SecurityGroups[[1]]$GroupId)
  }

  # Create security group
  cat_info(sprintf("   • Creating security group: %s...\n", sg_name))

  sg <- ec2$create_security_group(
    GroupName = sg_name,
    Description = "Security group for staRburst ECS workers",
    VpcId = vpc_id
  )

  sg_id <- sg$GroupId

  # Add egress rule (allow all outbound)
  # Ignore if rule already exists (security groups have default egress rules)
  tryCatch({
    ec2$authorize_security_group_egress(
      GroupId = sg_id,
      IpPermissions = list(
        list(
          IpProtocol = "-1",
          IpRanges = list(list(CidrIp = "0.0.0.0/0"))
        )
      )
    )
  }, error = function(e) {
    # Ignore duplicate rule errors
    if (!grepl("InvalidPermission.Duplicate", e$message, ignore.case = TRUE)) {
      stop(e)
    }
  })

  cat_success(sprintf("✓ Security group created: %s\n", sg_id))

  sg_id
}
