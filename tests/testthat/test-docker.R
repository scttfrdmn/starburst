test_that("build_environment_image validates Docker installation", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock system2 to simulate Docker not installed
  mockery::stub(
    build_environment_image,
    "system2",
    list(status = 1)
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

  # Mock file.exists
  mockery::stub(ensure_environment, "file.exists", function(...) TRUE)

  # Mock readLines to return mock renv.lock content
  mockery::stub(ensure_environment, "readLines", function(file, warn = FALSE) {
    c("{", "  \"R\": { \"Version\": \"4.3.0\" },", "  \"Packages\": {}", "}")
  })

  # Mock digest::digest
  mockery::stub(ensure_environment, "digest::digest", function(...) {
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

  # Mock file.exists
  mockery::stub(ensure_environment, "file.exists", function(...) TRUE)

  # Mock readLines to return mock renv.lock content
  mockery::stub(ensure_environment, "readLines", function(file, warn = FALSE) {
    c("{", "  \"R\": { \"Version\": \"4.3.0\" },", "  \"Packages\": {}", "}")
  })

  # Mock digest::digest
  mockery::stub(ensure_environment, "digest::digest", function(...) {
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
