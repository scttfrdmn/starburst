test_that("build_environment_image validates Docker installation", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock safe_system to simulate Docker not installed
  mockery::stub(
    build_environment_image,
    "safe_system",
    function(command, args, ...) {
      stop("docker: command not found")
    }
  )

  expect_error(
    build_environment_image("test-tag", "us-east-1"),
    "Docker is not installed"
  )
})

test_that("build_environment_image checks for renv.lock", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock Docker check to succeed
  mockery::stub(build_environment_image, "system2", function(...) {
    list()  # status = 0
  })

  # Mock Docker check to pass
  mockery::stub(build_environment_image, "safe_system", function(command, args, ...) {
    if (command == "docker" && any(grepl("--version", args))) {
      return(list(status = 0, stdout = "Docker version 20.10.0"))
    }
    stop("Unexpected command")
  })

  # Mock get_starburst_config (called first before checking renv.lock)
  mockery::stub(build_environment_image, "get_starburst_config", function() {
    list(aws_account_id = "123456789012")
  })

  # Mock ensure_base_image to avoid building base image
  mockery::stub(build_environment_image, "ensure_base_image", function(...) {
    "mock-base-image:latest"
  })

  # Mock file.exists to return FALSE for renv.lock
  mockery::stub(build_environment_image, "file.exists", function(path) {
    if (grepl("renv.lock", path)) return(FALSE)
    return(TRUE)
  })

  expect_error(
    build_environment_image("test-tag", "us-east-1"),
    "renv.lock not found"
  )
})

test_that("build_environment_image creates proper image tag", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # This is an integration-level test that would need full mocking
  # Skip for now - needs AWS credentials
  skip("Requires full AWS setup")
})

test_that("ensure_environment returns hash and image URI", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock renv::paths$lockfile
  mockery::stub(ensure_environment, "renv::paths$lockfile", function() {
    "test-lock.file"
  })

  # Mock file.exists and dir.exists so walk-up logic terminates quickly
  mockery::stub(ensure_environment, "file.exists", function(...) TRUE)
  mockery::stub(ensure_environment, "dir.exists", function(...) FALSE)

  # Mock compute_env_hash (replaces readLines + digest mocking since those
  # are now in a separate function that mockery stubs don't reach)
  mockery::stub(ensure_environment, "compute_env_hash", function(...) {
    "abc123hash"
  })

  # Mock get_starburst_config
  mockery::stub(ensure_environment, "get_starburst_config", function() {
    list(aws_account_id = "123456789012")
  })

  # Mock check_ecr_image_exists
  mockery::stub(ensure_environment, "check_ecr_image_exists", function(...) TRUE)

  result <- ensure_environment("us-east-1")

  expect_type(result, "list")
  expect_named(result, c("hash", "image_uri", "cluster"))
  expect_equal(result$hash, "abc123hash")
  expect_match(result$image_uri, "^123456789012\\.dkr\\.ecr\\.us-east-1")
  expect_match(result$image_uri, "abc123hash$")
})

test_that("ensure_environment builds image if not exists", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock renv::paths$lockfile
  mockery::stub(ensure_environment, "renv::paths$lockfile", function() {
    "test-lock.file"
  })

  # Mock file.exists and dir.exists so walk-up logic terminates quickly
  mockery::stub(ensure_environment, "file.exists", function(...) TRUE)
  mockery::stub(ensure_environment, "dir.exists", function(...) FALSE)

  # Mock compute_env_hash (replaces readLines + digest mocking since those
  # are now in a separate function that mockery stubs don't reach)
  mockery::stub(ensure_environment, "compute_env_hash", function(...) {
    "abc123hash"
  })

  # Mock get_starburst_config
  mockery::stub(ensure_environment, "get_starburst_config", function() {
    list(aws_account_id = "123456789012")
  })

  # Mock check_ecr_image_exists to return FALSE
  mockery::stub(ensure_environment, "check_ecr_image_exists", function(...) FALSE)

  # Mock build_environment_image
  build_called <- FALSE
  mockery::stub(ensure_environment, "build_environment_image", function(...) {
    build_called <<- TRUE
  })

  result <- ensure_environment("us-east-1")

  expect_true(build_called)
})

test_that("ensure_buildx_builder uses existing builder without creating", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  calls <- list()
  mockery::stub(ensure_buildx_builder, "safe_system",
    function(command, args, ...) {
      calls[[length(calls) + 1]] <<- args
      # inspect succeeds -> builder already exists
      invisible(list(status = 0))
    })

  result <- ensure_buildx_builder("starburst-builder")

  expect_true(result)
  # Exactly one call, and it is an inspect (no create)
  expect_length(calls, 1)
  expect_true(all(c("buildx", "inspect") %in% calls[[1]]))
  expect_false(any(vapply(calls, function(a) "create" %in% a, logical(1))))
})

test_that("ensure_buildx_builder creates builder when missing", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  calls <- list()
  mockery::stub(ensure_buildx_builder, "safe_system",
    function(command, args, ...) {
      calls[[length(calls) + 1]] <<- args
      # The first call is the existence probe (inspect) -> fail = missing.
      # Subsequent calls (create, confirming inspect) succeed.
      is_first <- length(calls) == 1
      if (is_first && "inspect" %in% args) {
        stop("no builder named starburst-builder")
      }
      invisible(list(status = 0))
    })

  result <- ensure_buildx_builder("starburst-builder")

  expect_true(result)
  # Must have attempted a create with the docker-container driver
  create_call <- Filter(function(a) "create" %in% a, calls)
  expect_length(create_call, 1)
  expect_true(all(c("--driver", "docker-container", "--bootstrap")
                  %in% create_call[[1]]))
  expect_true(all(c("--name", "starburst-builder") %in% create_call[[1]]))
})

test_that("ensure_buildx_builder returns FALSE when create fails", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  mockery::stub(ensure_buildx_builder, "safe_system",
    function(command, args, ...) {
      # Both the existence probe and the create attempt fail
      stop("buildx error")
    })

  expect_false(ensure_buildx_builder("starburst-builder"))
})

test_that("build_environment_image aborts when builder is unusable", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Docker --version check passes; buildx build must never be reached.
  mockery::stub(build_environment_image, "safe_system",
    function(command, args, ...) {
      if (any(grepl("--version", args))) {
        return(list(status = 0, stdout = "Docker version 20.10.0"))
      }
      if (any(args == "build")) stop("buildx build must not be called")
      list(status = 0)
    })
  mockery::stub(build_environment_image, "get_starburst_config",
                function() list(aws_account_id = "123456789012"))
  mockery::stub(build_environment_image, "ensure_base_image",
                function(...) "mock-base-image:latest")
  mockery::stub(build_environment_image, "file.exists", function(path) TRUE)
  mockery::stub(build_environment_image, "jsonlite::fromJSON",
                function(...) list(Packages = list()))
  mockery::stub(build_environment_image, "jsonlite::write_json", function(...) invisible())
  mockery::stub(build_environment_image, "file.copy", function(...) TRUE)
  mockery::stub(build_environment_image, "readLines", function(...) "FROM {{BASE_IMAGE}}")
  mockery::stub(build_environment_image, "writeLines", function(...) invisible())
  mockery::stub(build_environment_image, "get_ecr_client",
                function(...) list(get_authorization_token = function()
                  list(authorizationData = list(list(
                    authorizationToken = base64enc::base64encode(charToRaw("AWS:pw")),
                    proxyEndpoint = "https://example")))))
  # Builder cannot be made usable
  mockery::stub(build_environment_image, "ensure_buildx_builder", function(...) FALSE)

  expect_error(
    build_environment_image("test-tag", "us-east-1"),
    "starburst-builder"
  )
})
