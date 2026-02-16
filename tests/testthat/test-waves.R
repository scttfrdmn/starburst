test_that("wave queue initialized in backend", {
  skip_on_cran()

  # Create mock backend
  backend <- list(
    quota_limited = TRUE,
    workers_per_wave = 5,
    wave_queue = list(
      pending = list(),
      current_wave = 1,
      wave_futures = list(),
      completed = 0
    )
  )

  expect_equal(backend$wave_queue$current_wave, 1)
  expect_length(backend$wave_queue$pending, 0)
  expect_length(backend$wave_queue$wave_futures, 0)
})

test_that("get_wave_status returns NULL for non-quota-limited backends", {
  skip_on_cran()

  backend <- list(quota_limited = FALSE)

  result <- get_wave_status(backend)
  expect_null(result)
})

test_that("get_wave_status returns correct status", {
  skip_on_cran()

  backend <- list(
    quota_limited = TRUE,
    num_waves = 5,
    wave_queue = list(
      pending = list("t1", "t2"),
      current_wave = 2,
      wave_futures = list("t3" = list()),
      completed = 10
    )
  )

  result <- get_wave_status(backend)

  expect_type(result, "list")
  expect_equal(result$current_wave, 2)
  expect_equal(result$pending, 2)
  expect_equal(result$running, 1)
  expect_equal(result$completed, 10)
  expect_equal(result$total_waves, 5)
})
