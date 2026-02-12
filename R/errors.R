#' Error Handling for staRburst
#'
#' Improved error messages with context and solutions
#'
#' @name errors
#' @keywords internal
NULL

#' Create informative staRburst error
#'
#' Creates error messages with context, solutions, and links to documentation
#'
#' @param message Main error message
#' @param context Named list of contextual information
#' @param solution Suggested solution (optional)
#' @param call Calling function (default: sys.call(-1))
#'
#' @return Error condition with class "starburst_error"
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' if (vcpus_needed > vcpus_available) {
#'   stop(starburst_error(
#'     "Insufficient Fargate vCPU quota",
#'     context = list(
#'       workers_requested = workers,
#'       vcpus_needed = vcpus_needed,
#'       vcpus_available = vcpus_available,
#'       region = region
#'     ),
#'     solution = "Request quota increase or reduce workers"
#'   ))
#' }
#' }
starburst_error <- function(message,
                           context = list(),
                           solution = NULL,
                           call = sys.call(-1)) {

  # Build full message
  full_message <- message

  # Add context if provided
  if (length(context) > 0) {
    context_lines <- sapply(names(context), function(k) {
      value <- context[[k]]
      if (is.numeric(value)) {
        sprintf("  %s: %s", k, format(value, big.mark = ","))
      } else {
        sprintf("  %s: %s", k, as.character(value))
      }
    })
    full_message <- sprintf("%s\n\nContext:\n%s",
                           full_message,
                           paste(context_lines, collapse = "\n"))
  }

  # Add solution if provided
  if (!is.null(solution)) {
    full_message <- sprintf("%s\n\n💡 Solution:\n  %s",
                           full_message,
                           solution)
  }

  # Add link to troubleshooting guide
  full_message <- sprintf(
    "%s\n\n📖 For more help: vignette('troubleshooting', package = 'starburst')",
    full_message
  )

  # Create error condition
  structure(
    list(
      message = full_message,
      call = call,
      context = context,
      solution = solution
    ),
    class = c("starburst_error", "error", "condition")
  )
}

#' Quota exceeded error
#'
#' @keywords internal
quota_error <- function(resource,
                       requested,
                       available,
                       region,
                       workers = NULL,
                       cpu = NULL) {

  # Calculate what's possible
  if (!is.null(workers) && !is.null(cpu)) {
    vcpus_per_worker <- cpu
    max_possible_workers <- floor(available / vcpus_per_worker)

    solution <- sprintf(
      paste0(
        "Option 1: Request quota increase\n",
        "  • Go to AWS Console → Service Quotas → AWS Fargate\n",
        "  • Request increase to %d %s\n\n",
        "Option 2: Reduce workers to %d\n",
        "  plan(starburst, workers = %d)\n\n",
        "Option 3: Reduce CPU per worker\n",
        "  plan(starburst, workers = %d, cpu = 1, memory = \"2GB\")"
      ),
      ceiling(requested / 100) * 100, resource,
      max_possible_workers, max_possible_workers,
      workers
    )
  } else {
    solution <- sprintf(
      "Request quota increase in AWS Console → Service Quotas → AWS Fargate"
    )
  }

  starburst_error(
    sprintf("Insufficient %s quota", resource),
    context = list(
      resource = resource,
      requested = requested,
      available = available,
      region = region
    ),
    solution = solution
  )
}

#' Permission denied error
#'
#' @keywords internal
permission_error <- function(service,
                            operation,
                            resource = NULL,
                            iam_role = NULL) {

  context <- list(
    service = service,
    operation = operation
  )

  if (!is.null(resource)) {
    context$resource <- resource
  }

  if (!is.null(iam_role)) {
    context$iam_role <- iam_role
  }

  solution <- sprintf(
    paste0(
      "Option 1: Add IAM permissions\n",
      "  • Go to IAM → Roles → %s\n",
      "  • Add permission: %s:%s\n\n",
      "Option 2: Run starburst_setup() to create required roles\n",
      "  starburst_setup(bucket = 'your-bucket')\n\n",
      "Option 3: Check AWS credentials\n",
      "  library(paws.security.identity)\n",
      "  sts <- paws.security.identity::sts()\n",
      "  print(sts$get_caller_identity())"
    ),
    iam_role %||% "your-task-role",
    service,
    operation
  )

  starburst_error(
    sprintf("Permission denied: %s:%s", service, operation),
    context = context,
    solution = solution
  )
}

#' Task failure error
#'
#' @keywords internal
task_failure_error <- function(task_id,
                              reason = NULL,
                              exit_code = NULL,
                              log_stream = NULL) {

  context <- list(task_id = task_id)

  if (!is.null(reason)) {
    context$failure_reason <- reason
  }

  if (!is.null(exit_code)) {
    context$exit_code <- exit_code
  }

  solution <- "Check CloudWatch Logs for detailed error messages:\n"

  if (!is.null(log_stream)) {
    solution <- sprintf(
      paste0(
        "%s",
        "  1. Go to CloudWatch → Log Groups → /aws/ecs/starburst-worker\n",
        "  2. Find log stream: %s\n",
        "  3. Review error messages\n\n",
        "Or use AWS CLI:\n",
        "  aws logs tail /aws/ecs/starburst-worker --log-stream-names %s --follow"
      ),
      solution,
      log_stream,
      log_stream
    )
  } else {
    solution <- sprintf(
      paste0(
        "%s",
        "  1. Go to CloudWatch → Log Groups → /aws/ecs/starburst-worker\n",
        "  2. Search for task ID: %s\n",
        "  3. Review error messages"
      ),
      solution,
      task_id
    )
  }

  starburst_error(
    sprintf("Task failed: %s", task_id),
    context = context,
    solution = solution
  )
}

#' Worker validation error
#'
#' @keywords internal
worker_validation_error <- function(workers,
                                   max_allowed = 500) {

  starburst_error(
    "Invalid worker count",
    context = list(
      workers_requested = workers,
      max_allowed = max_allowed
    ),
    solution = sprintf(
      paste0(
        "Reduce workers to %d or less:\n",
        "  plan(starburst, workers = %d)\n\n",
        "For higher limits, contact AWS support:\n",
        "  https://docs.aws.amazon.com/servicequotas/"
      ),
      max_allowed,
      max_allowed
    )
  )
}

#' Package installation error
#'
#' @keywords internal
package_installation_error <- function(package,
                                      error_message = NULL) {

  context <- list(package = package)

  if (!is.null(error_message)) {
    context$error <- substring(error_message, 1, 200)  # Truncate long errors
  }

  solution <- sprintf(
    paste0(
      "Option 1: Install package locally first\n",
      "  install.packages('%s')\n",
      "  renv::snapshot()  # Update renv.lock\n\n",
      "Option 2: Check for system dependencies\n",
      "  # Package may need system libraries\n",
      "  # Add to Dockerfile.base if needed\n\n",
      "Option 3: Use development version\n",
      "  renv::install('user/repo')\n",
      "  renv::snapshot()"
    ),
    package
  )

  starburst_error(
    sprintf("Failed to install package: %s", package),
    context = context,
    solution = solution
  )
}
