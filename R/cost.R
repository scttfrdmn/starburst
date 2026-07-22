#' Cost estimation and pricing for staRburst
#'
#' @name cost
#' @keywords internal
NULL

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

    per_hour <- cost_per_worker_per_hour * workers
    list(
      # hourly_rate is the NORMALIZED field every consumer should use — the total
      # $/hour for the whole job, regardless of backend. (per_hour/per_worker kept
      # for back-compat.)
      hourly_rate = per_hour,
      per_worker = cost_per_worker_per_hour,
      per_hour = per_hour,
      total_estimated = per_hour * estimated_runtime_hours,
      backend = "FARGATE",
      instance_type = NULL,
      use_spot = FALSE
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
      hourly_rate = total_cost_per_hour,   # normalized total $/hour (see above)
      per_instance = instance_price,
      instances_needed = instances_needed,
      total_per_hour = total_cost_per_hour,
      total_estimated = total_cost_per_hour * estimated_runtime_hours,
      spot_discount = if (use_spot) "~70%" else "N/A",
      backend = "EC2",
      instance_type = instance_type,
      use_spot = use_spot,
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
