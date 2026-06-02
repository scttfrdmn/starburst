#' Utility functions for staRburst
#'
#' General-purpose helpers shared across the package. AWS-specific helpers live
#' in dedicated files: \code{aws-clients.R} (service clients), \code{cost.R}
#' (pricing), \code{images.R} (ECR/Docker), \code{task-definition.R} (ECS task
#' defs), \code{network.R} (VPC), \code{task-registry.R} (task ARNs), and
#' \code{s3-io.R} (S3 task/result transfer).
#'
#' @name utils
#' @keywords internal
NULL

#' Execute system command safely (no shell injection)
#'
#' @param command Command to execute (must be in whitelist)
#' @param args Character vector of arguments
#' @param allowed_commands Commands allowed to be executed
#' @param stdin Optional input to pass to stdin
#' @param ... Additional arguments passed to processx::run()
#' @return Result from processx::run()
#' @keywords internal
safe_system <- function(command,
                       args = character(),
                       allowed_commands = c("docker", "aws", "uname", "sysctl", "cat", "nproc"),
                       stdin = NULL,
                       stdout = "|",
                       stderr = "|",
                       ...) {
  # Validate command whitelist
  if (!command %in% allowed_commands) {
    stop(sprintf("Command not in whitelist: %s. Allowed: %s",
                 command, paste(allowed_commands, collapse = ", ")))
  }

  # Convert boolean stdout/stderr to processx format (TRUE = capture, FALSE = discard)
  if (isTRUE(stdout)) stdout <- "|"
  if (isFALSE(stdout)) stdout <- ""
  if (isTRUE(stderr)) stderr <- "|"
  if (isFALSE(stderr)) stderr <- ""

  # If stdin is a string that isn't a file path, write it to a temp file
  # processx::run() treats stdin as a file path, not file content
  stdin_file <- NULL
  if (!is.null(stdin) && stdin != "|" && !file.exists(stdin)) {
    stdin_file <- tempfile()
    writeLines(stdin, stdin_file)
    on.exit(unlink(stdin_file), add = TRUE)
    stdin <- stdin_file
  }

  # Use processx - automatically escapes, no shell
  result <- processx::run(
    command = command,
    args = args,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    error_on_status = FALSE,
    ...
  )

  if (result$status != 0) {
    stop(sprintf("Command '%s %s' failed (exit code %d):\n%s",
                 command, paste(args, collapse = " "),
                 result$status, result$stderr))
  }

  result
}

#' Infix null-coalesce operator
#'
#' @keywords internal
#' @noRd
`%||%` <- function(a, b) {
  if (is.null(a)) b else a
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
                 instance_type, paste(names(specs_map), collapse = ", ")))
  }

  specs <- specs_map[[instance_type]]
  list(
    vcpus = specs[1],
    memory_gb = specs[2]
  )
}
