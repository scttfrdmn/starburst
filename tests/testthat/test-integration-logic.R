test_that("task registry stores and retrieves tasks", {
  # Clean slate
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  # Store tasks
  store_task_arn("task-1", "arn:aws:ecs:us-east-1:123456789012:task/abc123")
  store_task_arn("task-2", "arn:aws:ecs:us-east-1:123456789012:task/def456")
  store_task_arn("task-3", "arn:aws:ecs:us-east-1:123456789012:task/ghi789")

  # Retrieve individual
  expect_equal(get_task_arn("task-1"), "arn:aws:ecs:us-east-1:123456789012:task/abc123")
  expect_equal(get_task_arn("task-2"), "arn:aws:ecs:us-east-1:123456789012:task/def456")

  # List all
  all_tasks <- list_task_arns()
  expect_length(all_tasks, 3)
  expect_true("task-1" %in% names(all_tasks))
  expect_true("task-2" %in% names(all_tasks))
  expect_true("task-3" %in% names(all_tasks))

  # Check timestamps exist
  expect_true(!is.null(all_tasks[["task-1"]]$submitted_at))
  expect_s3_class(all_tasks[["task-1"]]$submitted_at, "POSIXct")
})

test_that("ensure_environment returns proper structure", {
  skip_if_not_installed("mockery")

  # Mock all dependencies
  mockery::stub(ensure_environment, "renv::paths$lockfile", function() {
    "test.lock"
  })
  mockery::stub(ensure_environment, "file.exists", function(...) TRUE)
  mockery::stub(ensure_environment, "digest::digest", function(...) {
    "abc123hash"
  })
  mockery::stub(ensure_environment, "get_starburst_config", function() {
    list(aws_account_id = "123456789012")
  })
  mockery::stub(ensure_environment, "check_ecr_image_exists", function(...) TRUE)

  result <- ensure_environment("us-east-1")

  # Check structure
  expect_type(result, "list")
  expect_named(result, c("hash", "image_uri", "cluster"))

  # Check values
  expect_equal(result$hash, "abc123hash")
  expect_match(result$image_uri, "^123456789012\\.dkr\\.ecr\\.us-east-1\\.amazonaws\\.com/starburst-worker:abc123hash$")
})

test_that("wave status reporting works", {
  plan <- list(
    quota_limited = TRUE,
    num_waves = 5,
    wave_queue = list(
      pending = list("t1", "t2", "t3"),
      current_wave = 2,
      wave_futures = list("t4" = list(), "t5" = list()),
      completed = 10
    )
  )

  status <- get_wave_status(plan)

  expect_type(status, "list")
  expect_equal(status$current_wave, 2)
  expect_equal(status$pending, 3)
  expect_equal(status$running, 2)
  expect_equal(status$completed, 10)
  expect_equal(status$total_waves, 5)
})

test_that("wave status returns NULL for non-quota-limited", {
  plan <- list(quota_limited = FALSE)
  expect_null(get_wave_status(plan))
})

test_that("image URI format is correct", {
  skip_if_not_installed("mockery")

  mockery::stub(ensure_environment, "renv::paths$lockfile", function() "test.lock")
  mockery::stub(ensure_environment, "file.exists", function(...) TRUE)
  mockery::stub(ensure_environment, "digest::digest", function(...) "deadbeef123")
  mockery::stub(ensure_environment, "get_starburst_config", function() {
    list(aws_account_id = "999888777666")
  })
  mockery::stub(ensure_environment, "check_ecr_image_exists", function(...) TRUE)

  result <- ensure_environment("eu-west-1")

  expected_uri <- "999888777666.dkr.ecr.eu-west-1.amazonaws.com/starburst-worker:deadbeef123"
  expect_equal(result$image_uri, expected_uri)
})
