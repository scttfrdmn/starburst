test_that("get_task_registry creates registry if missing", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  registry <- get_task_registry()

  expect_true(is.environment(registry))
  expect_true(exists(".starburst_task_registry", envir = .starburst_env))
})

test_that("store_task_arn stores task information", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  store_task_arn("task-123", "arn:aws:ecs:us-east-1:123456789012:task/abc")

  registry <- get_task_registry()
  expect_true(exists("task-123", envir = registry))

  task_info <- registry[["task-123"]]
  expect_equal(task_info$task_arn, "arn:aws:ecs:us-east-1:123456789012:task/abc")
  expect_s3_class(task_info$submitted_at, "POSIXct")
})

test_that("get_task_arn retrieves stored ARN", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  store_task_arn("task-456", "arn:aws:ecs:us-east-1:123456789012:task/def")

  result <- get_task_arn("task-456")
  expect_equal(result, "arn:aws:ecs:us-east-1:123456789012:task/def")
})

test_that("get_task_arn returns NULL for unknown task", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  result <- get_task_arn("nonexistent-task")
  expect_null(result)
})

test_that("list_task_arns returns all stored tasks", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  store_task_arn("task-1", "arn:task-1")
  store_task_arn("task-2", "arn:task-2")
  store_task_arn("task-3", "arn:task-3")

  result <- list_task_arns()

  expect_length(result, 3)
  expect_true("task-1" %in% names(result))
  expect_true("task-2" %in% names(result))
  expect_true("task-3" %in% names(result))

  expect_equal(result[["task-1"]]$task_arn, "arn:task-1")
  expect_equal(result[["task-2"]]$task_arn, "arn:task-2")
})

test_that("list_task_arns returns empty list when no tasks", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  result <- list_task_arns()

  expect_type(result, "list")
  expect_length(result, 0)
})

test_that("task registry persists across function calls", {
  skip_on_cran()

  # Remove registry if it exists
  if (exists(".starburst_task_registry", envir = .starburst_env)) {
    rm(".starburst_task_registry", envir = .starburst_env)
  }

  store_task_arn("task-persist", "arn:persist")

  # Get registry again
  registry <- get_task_registry()
  expect_true(exists("task-persist", envir = registry))

  # Retrieve via function
  result <- get_task_arn("task-persist")
  expect_equal(result, "arn:persist")
})
