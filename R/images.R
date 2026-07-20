#' ECR repositories and Docker environment images for staRburst
#'
#' Functions for building and tracking the worker Docker images stored in ECR,
#' including the shared base image and per-environment images keyed by a hash
#' of the project's renv.lock.
#'
#' @name images
#' @keywords internal
NULL

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
    cat_success(sprintf("[OK] ECR auto-cleanup enabled: Images deleted after %d days\n", ttl_days))
  }, error = function(e) {
    cat_warn(sprintf("[WARNING] Failed to set ECR lifecycle policy: %s\n", e$message))
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
      cat_warn(sprintf("[WARNING] Image is %.0f days old (TTL: %d days), rebuilding...\n",
                         age_days, ttl_days))
      return(FALSE)  # Signal rebuild needed
    } else {
      cat_warn(sprintf("[WARNING] Image is %.0f days old (TTL: %d days)\n", age_days, ttl_days))
      cat_info("  AWS will auto-delete soon. Consider running a job to refresh.\n")
      return(TRUE)  # Use existing but warn
    }
  } else {
    days_remaining <- ttl_days - age_days
    cat_info(sprintf("[OK] Image age: %.0f days (%.0f days until auto-delete)\n",
                    age_days, days_remaining))
    return(TRUE)
  }
}

#' Compute environment image hash
#'
#' Computes the hash used to tag environment Docker images, combining the
#' renv.lock file contents with the starburst package version. This ensures
#' new images are built when either the R package environment or the starburst
#' worker script changes.
#'
#' @param lock_file Path to renv.lock file
#' @return MD5 hash string
#' @keywords internal
compute_env_hash <- function(lock_file) {
  # Read version from DESCRIPTION to handle dev vs installed discrepancies
  desc_path <- system.file("DESCRIPTION", package = "starburst")
  if (nzchar(desc_path)) {
    pkg_version <- read.dcf(desc_path, fields = "Version")[1, "Version"]
  } else {
    pkg_version <- as.character(utils::packageVersion("starburst"))
  }
  hash_input <- paste0(readLines(lock_file, warn = FALSE), collapse = "\n", pkg_version)
  digest::digest(hash_input, algo = "md5")
}

#' Ensure environment is ready
#'
#' @keywords internal
ensure_environment <- function(region) {
  # Get renv lock file hash
  lock_file <- renv::paths$lockfile()

  # Walk up directory tree to find the canonical package root renv.lock.
  # This is needed because testthat sets CWD to tests/testthat/ during tests,
  # causing renv::paths$lockfile() to return tests/testthat/renv.lock instead
  # of the package root renv.lock. We prefer the renv.lock closest to an R/
  # directory (indicating an R package root).
  search_dir <- dirname(lock_file)
  found_root_lock <- FALSE
  for (i in seq_len(10)) {
    parent <- dirname(search_dir)
    if (parent == search_dir) break  # reached filesystem root
    candidate <- file.path(parent, "renv.lock")
    if (file.exists(candidate) && dir.exists(file.path(parent, "R"))) {
      # Found a renv.lock next to an R/ directory - this is the package root
      lock_file <- candidate
      found_root_lock <- TRUE
      break
    }
    search_dir <- parent
  }

  if (!file.exists(lock_file)) {
    # No lockfile found anywhere - create a new snapshot as fallback
    # force = TRUE allows locally installed packages like starburst itself
    renv::snapshot(prompt = FALSE, force = TRUE)
    lock_file <- renv::paths$lockfile()
  }

  # Calculate hash using shared helper
  env_hash <- compute_env_hash(lock_file)

  # Get configuration for ECR URI
  config <- get_starburst_config()
  account_id <- config$aws_account_id
  ecr_uri <- sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker", account_id, region)
  image_uri <- sprintf("%s:%s", ecr_uri, env_hash)

  # Check if image exists in ECR
  image_exists <- check_ecr_image_exists(env_hash, region)

  if (!image_exists) {
    cat_info("[Setup] Building Docker image for R environment (this may take 5-10 minutes)...\n")
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

#' Check if a public base image exists (anonymously)
#'
#' Public ECR images are world-readable, so we can probe the manifest without
#' credentials via `docker manifest inspect`. Returns FALSE on any error (Docker
#' missing, network issue, tag absent) so callers fall back to a private build.
#'
#' @param image_uri Full public image reference, e.g.
#'   \code{public.ecr.aws/f8g1e7l5/base:r4.6.1}.
#' @return TRUE if the manifest is retrievable, FALSE otherwise.
#' @keywords internal
public_base_image_exists <- function(image_uri) {
  tryCatch({
    safe_system("docker", c("manifest", "inspect", image_uri),
                stdout = TRUE, stderr = TRUE)
    TRUE
  }, error = function(e) {
    FALSE
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

#' Ensure a buildx builder with the docker-container driver exists and is usable
#'
#' Idempotent across repeated runs and cross-platform (Windows/macOS/Linux).
#' Probes for an existing builder via \code{docker buildx inspect}; creates it
#' only when missing; bootstraps it so it is ready to build. A docker-container
#' driver is required for multi-platform (\code{linux/amd64,linux/arm64})
#' builds. Does not mutate the user's default buildx context (no \code{--use});
#' the build pins the builder explicitly via \code{--builder}.
#'
#' Returns TRUE if the named builder is usable, FALSE otherwise, and never
#' throws -- callers decide policy. This fixes the failure mode where
#' \code{buildx create} errored on an already-existing builder, the error was
#' swallowed, and the subsequent \code{buildx build} failed with "existing
#' instance for <name> but no append mode" (GitHub #24).
#'
#' @param builder_name Name of the buildx builder (default "starburst-builder")
#' @return TRUE if the named builder is usable, FALSE otherwise
#' @keywords internal
ensure_buildx_builder <- function(builder_name = "starburst-builder") {
  # stdout/stderr are captured (not discarded) so that when a buildx call fails
  # safe_system()'s stop() carries the real stderr, instead of the failure being
  # swallowed here and surfacing later as an opaque "no builder found" at the
  # buildx build step (GitHub #24/#30).

  # 1. Does it already exist? inspect returns non-zero (-> error) if not;
  #    --bootstrap also boots an existing-but-stopped builder.
  exists <- tryCatch({
    safe_system("docker", c("buildx", "inspect", "--bootstrap", builder_name),
                stdout = TRUE, stderr = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (exists) {
    return(TRUE)
  }

  # 2. Missing: create it with the docker-container driver and bootstrap it.
  created <- tryCatch({
    safe_system(
      "docker",
      c("buildx", "create", "--name", builder_name,
        "--driver", "docker-container", "--bootstrap"),
      stdout = TRUE, stderr = TRUE
    )
    TRUE
  }, error = function(e) {
    cat_warn(sprintf("Warning: failed to create buildx builder '%s': %s\n",
                     builder_name, conditionMessage(e)))
    FALSE
  })

  if (!created) {
    return(FALSE)
  }

  # 3. Confirm it booted and is selectable. 'inspect' verifies it is usable;
  #    'use' registers it as current so the explicit --builder reference in
  #    buildx build resolves (guards against the create not persisting).
  tryCatch({
    safe_system("docker", c("buildx", "inspect", "--bootstrap", builder_name),
                stdout = TRUE, stderr = TRUE)
    safe_system("docker", c("buildx", "use", builder_name),
                stdout = TRUE, stderr = TRUE)
    TRUE
  }, error = function(e) {
    cat_warn(sprintf("Warning: buildx builder '%s' created but not usable: %s\n",
                     builder_name, conditionMessage(e)))
    FALSE
  })
}

#' Build base Docker image with common dependencies
#'
#' @keywords internal
build_base_image <- function(region) {
  cat_info("[Docker] Building staRburst base image...\n")

  # Validate Docker is installed
  tryCatch({
    safe_system("docker", c("--version"), stdout = TRUE, stderr = TRUE)
  }, error = function(e) {
    stop("Docker is not installed or not accessible. Please install Docker: https://docs.docker.com/get-docker/")
  })

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
        cat_info("   * Image expired, rebuilding...\n")
        # Continue to rebuild below
      } else {
        cat_success(sprintf("[OK] Base image already exists: %s\n", base_uri))
        return(base_uri)
      }
    } else {
      cat_success(sprintf("[OK] Base image already exists: %s\n", base_uri))
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

    # Dockerfile.base takes R_VERSION as a real Docker build arg (passed below).
    # The legacy {{R_VERSION}} gsub is kept for backward compatibility with any
    # older template copy; on the current template it is a harmless no-op.
    template_content <- readLines(dockerfile_template)
    dockerfile_content <- gsub("\\{\\{R_VERSION\\}\\}", r_version, template_content)
    writeLines(dockerfile_content, file.path(build_dir, "Dockerfile"))

    cat_info(sprintf("   * Build directory: %s\n", build_dir))
    cat_info(sprintf("   * R version: %s\n", r_version))
    cat_info("   * This includes system deps + renv + future/globals/qs/paws\n")
    cat_info("   * This is a one-time build (3-5 min), reused by all projects\n")

    # Authenticate with ECR
    cat_info("   * Authenticating with ECR...\n")
    ecr <- get_ecr_client(region)
    auth_token <- ecr$get_authorization_token()

    if (length(auth_token$authorizationData) == 0) {
      stop("Failed to get ECR authorization token")
    }

    token_data <- auth_token$authorizationData[[1]]
    decoded_token <- rawToChar(base64enc::base64decode(token_data$authorizationToken))
    token_parts <- strsplit(decoded_token, ":")[[1]]
    password <- token_parts[2]

    # Docker login - pass password via stdin (secure, no shell exposure)
    login_result <- tryCatch({
      safe_system(
        "docker",
        c("login", "--username", "AWS", "--password-stdin", token_data$proxyEndpoint),
        stdin = password
      )
      TRUE
    }, error = function(e) {
      stop(sprintf("Failed to authenticate with ECR for account %s in region %s: %s",
                  account_id, region, e$message))
    })

    # Build multi-platform base image
    ecr_uri <- sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker", account_id, region)
    image_tag <- sprintf("%s:%s", ecr_uri, base_tag)
    cat_info(sprintf("   * Building multi-platform base image: %s\n", image_tag))
    cat_info("   * Platforms: linux/amd64, linux/arm64\n")

    # Ensure a docker-container buildx builder exists (required for multi-platform).
    if (!ensure_buildx_builder("starburst-builder")) {
      stop(paste0(
        "Could not create or access the 'starburst-builder' buildx builder, ",
        "which is required for multi-platform (linux/amd64, linux/arm64) builds. ",
        "Ensure Docker is running and that 'docker buildx' is available, then retry. ",
        "Inspect builders with: docker buildx ls"
      ))
    }

    # Build and push multi-platform image (no cache for clean multi-platform build)
    safe_system(
      "docker",
      c("buildx", "build",
        "--builder", "starburst-builder",
        "--platform", "linux/amd64,linux/arm64",
        "--build-arg", sprintf("R_VERSION=%s", r_version),
        "--no-cache",
        "-t", image_tag,
        "--push",
        build_dir)
    )

    cat_success(sprintf("[OK] Base image built and pushed: %s\n", image_tag))
    cat_success("[OK] This base image will be reused by all future projects\n")

    return(image_tag)

  }, error = function(e) {
    cat_error(sprintf("[ERROR] Base image build failed: %s\n", e$message))
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
    # Public ECR (no auth needed, instant pull). Published by the
    # build-base-images.yml workflow under this account's public ECR alias.
    # (The friendly 'starburst' alias needs an AWS Support request; until then
    # images live under the default alias 'f8g1e7l5'.)
    return(sprintf("public.ecr.aws/f8g1e7l5/base:r%s", r_version))
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
    # Try the published public base image first; fall back to a private build
    # if it isn't available for this R version (or can't be reached).
    base_uri <- get_base_image_source(use_public = TRUE)
    cat_info(sprintf("Trying public base image: %s\n", base_uri))

    if (public_base_image_exists(base_uri)) {
      cat_success(sprintf("[OK] Using public base image: %s\n", base_uri))
      return(base_uri)
    }

    cat_warn(sprintf("   Public base image not available for R %s\n", r_version))
    cat_info("   Falling back to private base image build...\n")
    use_public <- FALSE
  }

  if (!use_public) {
    # Use private base image (build if needed)
    if (!check_ecr_image_exists(base_tag, region)) {
      cat_info("[Package] Base image not found in private ECR, building it now...\n")
      cat_info("   (This will take 3-5 minutes, but only needed once per R version)\n")
      build_base_image(region)
    } else {
      base_uri <- get_base_image_uri(region)
      cat_info(sprintf("[OK] Using existing private base image: %s\n", base_uri))
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
  cat_info("[Docker] Building project Docker image...\n")

  # Validate Docker is installed
  tryCatch({
    safe_system("docker", c("--version"), stdout = TRUE, stderr = TRUE)
  }, error = function(e) {
    stop("Docker is not installed or not accessible. Please install Docker: https://docs.docker.com/get-docker/")
  })

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

    cat_info(sprintf("   * Build directory: %s\n", build_dir))
    cat_info(sprintf("   * Base image: %s\n", base_image_uri))
    cat_info("   * Building only project-specific packages...\n")

    # Authenticate with ECR
    cat_info("   * Authenticating with ECR...\n")
    ecr <- get_ecr_client(region)
    auth_token <- ecr$get_authorization_token()

    if (length(auth_token$authorizationData) == 0) {
      stop("Failed to get ECR authorization token")
    }

    token_data <- auth_token$authorizationData[[1]]
    decoded_token <- rawToChar(base64enc::base64decode(token_data$authorizationToken))
    token_parts <- strsplit(decoded_token, ":")[[1]]
    password <- token_parts[2]

    # Docker login - pass password via stdin (secure, no shell exposure)
    login_result <- tryCatch({
      safe_system(
        "docker",
        c("login", "--username", "AWS", "--password-stdin", token_data$proxyEndpoint),
        stdin = password
      )
      TRUE
    }, error = function(e) {
      stop(sprintf("Failed to authenticate with ECR for account %s in region %s: %s",
                  account_id, region, e$message))
    })

    # Build multi-platform image
    image_tag <- sprintf("%s:%s", ecr_uri, tag)
    cat_info(sprintf("   * Building multi-platform image: %s\n", image_tag))
    cat_info("   * Platforms: linux/amd64, linux/arm64\n")

    # Ensure a docker-container buildx builder exists (required for multi-platform).
    if (!ensure_buildx_builder("starburst-builder")) {
      stop(paste0(
        "Could not create or access the 'starburst-builder' buildx builder, ",
        "which is required for multi-platform (linux/amd64, linux/arm64) builds. ",
        "Ensure Docker is running and that 'docker buildx' is available, then retry. ",
        "Inspect builders with: docker buildx ls"
      ))
    }

    # Build and push multi-platform image (no cache for clean multi-platform build)
    safe_system(
      "docker",
      c("buildx", "build",
        "--builder", "starburst-builder",
        "--platform", "linux/amd64,linux/arm64",
        "--no-cache",
        "-t", image_tag,
        "--push",
        build_dir)
    )

    cat_success(sprintf("[OK] Image built and pushed: %s\n", image_tag))

    return(image_tag)

  }, error = function(e) {
    cat_error(sprintf("[ERROR] Image build failed: %s\n", e$message))
    stop(e)
  })
}

#' Build initial environment
#'
#' @keywords internal
build_initial_environment <- function(region) {
  ensure_environment(region)
}
