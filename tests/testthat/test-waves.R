test_that("wave queue initialized in plan", {
  skip_on_cran()

  # Create mock plan
  plan <- list(
    quota_limited = TRUE,
    workers_per_wave = 5,
    wave_queue = list(
      pending = list(),
      current_wave = 1,
      wave_futures = list(),
      completed = 0
    )
  )

  expect_equal(plan$wave_queue$current_wave, 1)
  expect_length(plan$wave_queue$pending, 0)
  expect_length(plan$wave_queue$wave_futures, 0)
})

test_that("add_to_queue adds task to pending", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Create mock plan
  plan <- list(
    quota_limited = TRUE,
    workers_per_wave = 5,
    wave_queue = list(
      pending = list(),
      current_wave = 1,
      wave_futures = list(),
      completed = 0
    )
  )

  # Mock check_and_submit_wave to return the plan unchanged
  mockery::stub(add_to_queue, "check_and_submit_wave", function(p) p)

  # Capture the returned plan
  plan <- add_to_queue("task-1", plan)

  expect_length(plan$wave_queue$pending, 1)
  expect_equal(plan$wave_queue$pending[[1]], "task-1")
})

test_that("check_and_submit_wave submits first wave", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  submitted_tasks <- character(0)

  # Create mock plan
  plan <- list(
    quota_limited = TRUE,
    workers_per_wave = 2,
    wave_queue = list(
      pending = list("task-1", "task-2", "task-3"),
      current_wave = 1,
      wave_futures = list(),
      completed = 0
    )
  )

  # Mock submit_fargate_task
  mockery::stub(check_and_submit_wave, "submit_fargate_task", function(task_id, plan) {
    submitted_tasks <<- c(submitted_tasks, task_id)
  })

  # Capture the returned plan
  plan <- check_and_submit_wave(plan)

  # Should submit 2 tasks (workers_per_wave)
  expect_equal(submitted_tasks, c("task-1", "task-2"))
  expect_length(plan$wave_queue$pending, 1)
  expect_equal(plan$wave_queue$pending[[1]], "task-3")
  expect_equal(plan$wave_queue$current_wave, 2)
})

test_that("check_and_submit_wave waits for current wave to complete", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Create mock futures that are not resolved
  mock_future <- structure(
    list(task_id = "task-1", state = "running"),
    class = "starburst_future"
  )

  # Create mock plan with running futures
  plan <- list(
    quota_limited = TRUE,
    workers_per_wave = 2,
    wave_queue = list(
      pending = list("task-3", "task-4"),
      current_wave = 2,
      wave_futures = list("task-1" = mock_future, "task-2" = mock_future),
      completed = 0
    )
  )

  # Mock resolved to return FALSE
  mockery::stub(check_and_submit_wave, "resolved", function(...) FALSE)

  submitted <- FALSE
  mockery::stub(check_and_submit_wave, "submit_fargate_task", function(...) {
    submitted <<- TRUE
  })

  # Capture the returned plan
  plan <- check_and_submit_wave(plan)

  # Should NOT submit new tasks
  expect_false(submitted)
  expect_length(plan$wave_queue$wave_futures, 2)
})

test_that("check_and_submit_wave removes completed futures", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Create mock futures
  completed_future <- structure(
    list(task_id = "task-1", state = "completed", value = 42),
    class = "starburst_future"
  )

  running_future <- structure(
    list(task_id = "task-2", state = "running"),
    class = "starburst_future"
  )

  # Create mock plan
  plan <- list(
    quota_limited = TRUE,
    workers_per_wave = 2,
    wave_queue = list(
      pending = list(),
      current_wave = 2,
      wave_futures = list(
        "task-1" = completed_future,
        "task-2" = running_future
      ),
      completed = 0
    )
  )

  # Mock resolved - task-1 is done, task-2 is not
  mockery::stub(check_and_submit_wave, "resolved", function(future) {
    future$task_id == "task-1"
  })

  # Capture the returned plan
  plan <- check_and_submit_wave(plan)

  # Should remove completed future
  expect_length(plan$wave_queue$wave_futures, 1)
  expect_equal(names(plan$wave_queue$wave_futures), "task-2")
  expect_equal(plan$wave_queue$completed, 1)
})

test_that("check_and_submit_wave starts next wave after completion", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  submitted_tasks <- character(0)

  # Create mock plan with all futures completed and pending tasks
  plan <- list(
    quota_limited = TRUE,
    workers_per_wave = 2,
    wave_queue = list(
      pending = list("task-3", "task-4"),
      current_wave = 2,
      wave_futures = list(),  # Empty - previous wave completed
      completed = 2
    )
  )

  # Mock submit_fargate_task
  mockery::stub(check_and_submit_wave, "submit_fargate_task", function(task_id, plan) {
    submitted_tasks <<- c(submitted_tasks, task_id)
  })

  # Capture the returned plan
  plan <- check_and_submit_wave(plan)

  # Should submit next wave
  expect_equal(submitted_tasks, c("task-3", "task-4"))
  expect_length(plan$wave_queue$pending, 0)
  expect_equal(plan$wave_queue$current_wave, 3)
})

test_that("get_wave_status returns NULL for non-quota-limited plans", {
  skip_on_cran()

  plan <- list(quota_limited = FALSE)

  result <- get_wave_status(plan)
  expect_null(result)
})

test_that("get_wave_status returns correct status", {
  skip_on_cran()

  plan <- list(
    quota_limited = TRUE,
    num_waves = 5,
    wave_queue = list(
      pending = list("t1", "t2"),
      current_wave = 2,
      wave_futures = list("t3" = list()),
      completed = 10
    )
  )

  result <- get_wave_status(plan)

  expect_type(result, "list")
  expect_equal(result$current_wave, 2)
  expect_equal(result$pending, 2)
  expect_equal(result$running, 1)
  expect_equal(result$completed, 10)
  expect_equal(result$total_waves, 5)
})

test_that("resolved.starburst_future triggers wave checks", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Create mock future that is queued
  future <- structure(
    list(
      task_id = "task-1",
      state = "queued",
      value = NULL,
      plan = list(
        quota_limited = TRUE,
        wave_queue = list(
          pending = list("task-1"),
          wave_futures = list(),
          current_wave = 1,
          completed = 0
        )
      )
    ),
    class = "starburst_future"
  )

  wave_checked <- FALSE
  mockery::stub(resolved.starburst_future, "check_and_submit_wave", function(plan) {
    wave_checked <<- TRUE
    return(plan)  # Return the plan
  })

  mockery::stub(resolved.starburst_future, "result_exists", function(...) FALSE)

  resolved.starburst_future(future)

  expect_true(wave_checked)
})
