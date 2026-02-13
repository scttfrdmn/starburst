#' Check Fargate vCPU quota
#'
#' @param region AWS region
#' @return List with quota information
#' @keywords internal
check_fargate_quota <- function(region) {
  sq <- get_service_quotas_client(region)

  tryCatch({
    # Get current quota
    quota_response <- sq$get_service_quota(
      ServiceCode = "fargate",
      QuotaCode = "L-3032A538"  # Fargate vCPU quota code
    )

    current_limit <- quota_response$Quota$Value

    # Check for pending increase requests
    pending_response <- sq$list_requested_service_quota_change_history_by_quota(
      ServiceCode = "fargate",
      QuotaCode = "L-3032A538",
      Status = "PENDING"
    )

    has_pending <- length(pending_response$RequestedQuotas) > 0

    # Get current usage (approximate from CloudWatch)
    current_usage <- get_current_vcpu_usage(region)

    list(
      limit = current_limit,
      used = current_usage,
      available = current_limit - current_usage,
      increase_pending = has_pending,
      pending_requests = pending_response$RequestedQuotas
    )

  }, error = function(e) {
    # Fallback if Service Quotas API not available
    warning(sprintf("Could not check quota: %s", e$message))
    list(
      limit = 100,  # Conservative default
      used = 0,
      available = 100,
      increase_pending = FALSE,
      pending_requests = list()
    )
  })
}

#' Request quota increase
#'
#' @param service AWS service (e.g., "fargate")
#' @param quota_code Service quota code
#' @param desired_value Desired quota value
#' @param region AWS region
#' @param reason Justification for increase
#'
#' @return Case ID if successful, NULL if failed
#' @keywords internal
request_quota_increase <- function(service,
                                   quota_code,
                                   desired_value,
                                   region,
                                   reason = "") {
  sq <- get_service_quotas_client(region)

  tryCatch({
    response <- sq$request_service_quota_increase(
      ServiceCode = service,
      QuotaCode = quota_code,
      DesiredValue = desired_value
    )

    case_id <- response$RequestedQuota$CaseId

    # Save request to local tracking
    save_quota_request(case_id, service, quota_code, desired_value, region)

    return(case_id)

  }, error = function(e) {
    cat_error(sprintf("Failed to request quota increase: %s\n", e$message))
    cat_info("\nPlease request manually:\n")
    cat_info(sprintf(
      "  https://console.aws.amazon.com/servicequotas/home/services/%s/quotas/%s\n",
      service, quota_code
    ))
    return(NULL)
  })
}

#' Request quota increase (user-facing)
#'
#' @param vcpus Desired vCPU quota
#' @param region AWS region (default: from config)
#'
#' @export
#'
#' @examples
#' \dontrun{
#' starburst_request_quota_increase(vcpus = 500)
#' }
starburst_request_quota_increase <- function(vcpus = 500, region = NULL) {

  config <- get_starburst_config()
  region <- region %||% config$region

  # Check current quota
  quota_info <- check_fargate_quota(region)

  if (vcpus <= quota_info$limit) {
    cat_info(sprintf(
      "Current quota (%d vCPUs) already meets or exceeds requested (%d vCPUs)\n",
      quota_info$limit, vcpus
    ))
    return(invisible(FALSE))
  }

  if (quota_info$increase_pending) {
    cat_warn("You already have a pending quota increase request\n")

    if (length(quota_info$pending_requests) > 0) {
      for (req in quota_info$pending_requests) {
        cat_info(sprintf(
          "  Case ID: %s, Requested: %.0f vCPUs\n",
          req$CaseId, req$DesiredValue
        ))
      }
    }

    return(invisible(FALSE))
  }

  cat_info(sprintf("Requesting Fargate vCPU quota increase:\n"))
  cat_info(sprintf("  Current: %d vCPUs\n", quota_info$limit))
  cat_info(sprintf("  Requested: %d vCPUs\n", vcpus))
  cat_info(sprintf("  Region: %s\n", region))

  if (interactive()) {
    response <- readline("\nProceed? [y/n]: ")
    if (tolower(response) != "y") {
      cat_info("Request cancelled\n")
      return(invisible(FALSE))
    }
  }

  case_id <- request_quota_increase(
    service = "fargate",
    quota_code = "L-3032A538",
    desired_value = vcpus,
    region = region,
    reason = sprintf("staRburst parallel R computing - need %d vCPUs for workloads", vcpus)
  )

  if (!is.null(case_id)) {
    cat_success(sprintf("\n[OK] Quota increase requested (Case ID: %s)\n", case_id))
    cat_success("[OK] AWS typically approves these requests within 1-24 hours\n")
    cat_success("[OK] You'll receive an email when the request is processed\n")
    cat_info("\nCheck status: starburst_quota_status()\n")
    return(invisible(TRUE))
  }

  invisible(FALSE)
}

#' Show quota status
#'
#' @param region AWS region (default: from config)
#'
#' @export
#'
#' @examples
#' \dontrun{
#' starburst_quota_status()
#' }
starburst_quota_status <- function(region = NULL) {

  config <- get_starburst_config()
  region <- region %||% config$region

  cat_header("Fargate vCPU Quota Status\n")

  quota_info <- check_fargate_quota(region)

  cat_info(sprintf("Region: %s\n\n", region))
  cat_info(sprintf("Current Quota: %d vCPUs\n", quota_info$limit))
  cat_info(sprintf("Currently Used: %d vCPUs\n", quota_info$used))
  cat_info(sprintf("Available: %d vCPUs\n", quota_info$available))

  # Show what this allows
  workers_4cpu <- floor(quota_info$available / 4)
  workers_8cpu <- floor(quota_info$available / 8)

  cat_info(sprintf("\nCapacity:\n"))
  cat_info(sprintf("  • ~%d workers with 4 vCPUs each\n", workers_4cpu))
  cat_info(sprintf("  • ~%d workers with 8 vCPUs each\n", workers_8cpu))

  # Pending requests
  if (quota_info$increase_pending) {
    cat_warn("\nPending Quota Increase Requests:\n")
    for (req in quota_info$pending_requests) {
      cat_info(sprintf(
        "  • Case ID: %s\n    Requested: %.0f vCPUs\n    Status: %s\n    Created: %s\n",
        req$CaseId,
        req$DesiredValue,
        req$Status,
        format(req$Created, "%Y-%m-%d %H:%M")
      ))
    }
  }

  # Recommendations
  if (quota_info$limit < 500) {
    cat_warn("\n[TIP] Recommendation:\n")
    cat_info("  For typical parallel workloads, we recommend 500+ vCPUs\n")
    cat_info("  Request increase: starburst_request_quota_increase(vcpus = 500)\n")
  } else {
    cat_success("\n[OK] Quota is sufficient for most workloads\n")
  }

  # Show historical requests
  history <- load_quota_history()
  if (length(history) > 0) {
    cat_info("\nRecent Requests:\n")
    for (h in utils::tail(history, 5)) {
      cat_info(sprintf(
        "  • %s: Requested %d vCPUs (Case: %s)\n",
        format(h$timestamp, "%Y-%m-%d"),
        h$desired_value,
        h$case_id
      ))
    }
  }

  invisible(quota_info)
}

#' Suggest appropriate quota based on needs
#'
#' @param vcpus_needed vCPUs needed
#' @return Suggested quota value
#' @keywords internal
suggest_quota <- function(vcpus_needed) {
  # Round up to standard increments
  # AWS prefers requests at these levels

  quotas <- c(100, 200, 500, 1000, 2000, 5000, 10000)

  # Find smallest quota that's >= needed + 25% buffer
  needed_with_buffer <- vcpus_needed * 1.25

  for (quota in quotas) {
    if (quota >= needed_with_buffer) {
      return(quota)
    }
  }

  # If we get here, they need more than 10k
  ceiling(needed_with_buffer / 1000) * 1000
}

#' Get current vCPU usage
#'
#' @keywords internal
get_current_vcpu_usage <- function(region) {
  ecs <- get_ecs_client(region)

  tryCatch({
    # List all clusters
    clusters_response <- ecs$list_clusters()

    if (length(clusters_response$clusterArns) == 0) {
      return(0)
    }

    # Get running tasks for each cluster
    total_vcpus <- 0

    for (cluster_arn in clusters_response$clusterArns) {
      tasks_response <- ecs$list_tasks(
        cluster = cluster_arn,
        desiredStatus = "RUNNING",
        launchType = "FARGATE"
      )

      if (length(tasks_response$taskArns) == 0) {
        next
      }

      # Describe tasks to get CPU allocation
      tasks_detail <- ecs$describe_tasks(
        cluster = cluster_arn,
        tasks = tasks_response$taskArns
      )

      for (task in tasks_detail$tasks) {
        # Parse CPU from task definition
        # CPU is in units (1024 = 1 vCPU)
        cpu_units <- as.numeric(task$cpu)
        vcpus <- cpu_units / 1024
        total_vcpus <- total_vcpus + vcpus
      }
    }

    return(total_vcpus)

  }, error = function(e) {
    # If we can't get usage, return 0
    return(0)
  })
}

#' Save quota request to local history
#'
#' @keywords internal
save_quota_request <- function(case_id, service, quota_code, desired_value, region) {
  history_file <- file.path(config_dir(), "quota_history.rds")

  # Load existing history
  if (file.exists(history_file)) {
    history <- readRDS(history_file)
  } else {
    history <- list()
  }

  # Add new request
  request <- list(
    case_id = case_id,
    service = service,
    quota_code = quota_code,
    desired_value = desired_value,
    region = region,
    timestamp = Sys.time()
  )

  history <- c(history, list(request))

  # Save
  saveRDS(history, history_file)

  invisible(NULL)
}

#' Load quota request history
#'
#' @keywords internal
load_quota_history <- function() {
  history_file <- file.path(config_dir(), "quota_history.rds")

  if (!file.exists(history_file)) {
    return(list())
  }

  readRDS(history_file)
}

#' Check if quota is sufficient for plan
#'
#' @keywords internal
check_quota_sufficient <- function(workers, cpu, region) {
  quota_info <- check_fargate_quota(region)
  needed <- workers * cpu

  list(
    sufficient = needed <= quota_info$available,
    needed = needed,
    available = quota_info$available,
    workers_per_wave = floor(quota_info$available / cpu),
    num_waves = ceiling(workers / floor(quota_info$available / cpu))
  )
}

#' Monitor quota increase request
#'
#' @param case_id Case ID from quota increase request
#' @param region AWS region
#'
#' @export
#'
#' @examples
#' \dontrun{
#' starburst_check_quota_request("case-12345")
#' }
starburst_check_quota_request <- function(case_id, region = NULL) {
  config <- get_starburst_config()
  region <- region %||% config$region

  sq <- get_service_quotas_client(region)

  tryCatch({
    response <- sq$get_requested_service_quota_change(
      RequestId = case_id
    )

    req <- response$RequestedQuota

    cat_info(sprintf("Quota Increase Request: %s\n\n", case_id))
    cat_info(sprintf("Service: %s\n", req$ServiceCode))
    cat_info(sprintf("Status: %s\n", req$Status))
    cat_info(sprintf("Requested Value: %.0f\n", req$DesiredValue))
    cat_info(sprintf("Created: %s\n", format(req$Created, "%Y-%m-%d %H:%M")))

    if (!is.null(req$LastUpdated)) {
      cat_info(sprintf("Last Updated: %s\n", format(req$LastUpdated, "%Y-%m-%d %H:%M")))
    }

    if (req$Status == "APPROVED") {
      cat_success("\n[OK] Request approved!\n")
      cat_info("Your new quota is now active\n")
    } else if (req$Status == "DENIED") {
      cat_error("\n[ERROR] Request denied\n")
      if (!is.null(req$DenialReason)) {
        cat_info(sprintf("Reason: %s\n", req$DenialReason))
      }
    } else if (req$Status == "PENDING") {
      cat_warn("\n⏳ Request still pending\n")
      cat_info("AWS typically processes these within 1-24 hours\n")
    }

    invisible(req)

  }, error = function(e) {
    cat_error(sprintf("Failed to check request status: %s\n", e$message))
    invisible(NULL)
  })
}
