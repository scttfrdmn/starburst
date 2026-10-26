# End-to-end, offline: every public entry point that runs work on ephemeral
# workers, through the real client code and the shipped worker script (see
# helper-roundtrip.R). Any of #63-#65 or the backend/run_task/sizing bugs
# fixed alongside them fails here.

skip_if_not_installed("qs2")
skip_if_not_installed("paws.storage")

test_that("plan(starburst): value(), globals and worker errors round-trip", {
  aws <- local_fake_aws()
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)

  capture.output(future::plan(starburst, workers = 2, instance_type = "c7g.xlarge"))

  expect_equal(future::value(future::future(1 + 1)), 2)

  y <- 21
  expect_equal(future::value(future::future(y * 2)), 42)

  err <- tryCatch(future::value(future::future(stop("boom-from-worker"))),
                  error = identity)
  expect_match(conditionMessage(err), "boom-from-worker")
  expect_no_match(conditionMessage(err), "INTERNAL ERROR")

  expect_gte(aws$ecs$calls$n, 3)
  future::plan(future::sequential)
})

test_that("plan(starburst) works with future.apply", {
  skip_if_not_installed("future.apply")
  aws <- local_fake_aws()
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)

  capture.output(future::plan(starburst, workers = 2, instance_type = "c7g.xlarge"))
  res <- future.apply::future_lapply(1:3, function(i) i^2)
  expect_equal(res, list(1, 4, 9))
})

test_that("starburst_map(): results and worker errors round-trip", {
  aws <- local_fake_aws()

  capture.output(
    res <- starburst_map(1:3, function(x) x^2, workers = 2,
                         instance_type = "c7g.xlarge", .progress = FALSE)
  )
  expect_equal(res, list(1, 4, 9))
  expect_identical(aws$ecs$calls$last$cluster, "starburst-cluster")

  capture.output(
    err <- tryCatch(starburst_map(1:2, function(x) stop("map-boom"), workers = 2,
                                  instance_type = "c7g.xlarge", .progress = FALSE),
                    error = identity)
  )
  expect_match(conditionMessage(err), "map-boom")
})

test_that("starburst_map() default arguments round-trip", {
  # Defaults are what users hit first (8GB/4 vCPU must be resized to fit)
  aws <- local_fake_aws()
  capture.output(res <- starburst_map(1:2, function(x) x + 1, .progress = FALSE))
  expect_equal(res, list(2, 3))
})

test_that("starburst_cluster(): map round-trips and shutdown leaves the plan alone", {
  aws <- local_fake_aws()
  local_mocked_bindings(cleanup_cluster = function(...) invisible(NULL))
  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)

  capture.output(cl <- starburst_cluster(workers = 2, instance_type = "c7g.xlarge"))
  capture.output(res <- cl$map(1:2, function(x) x + 100, .progress = FALSE))
  expect_equal(res, list(101, 102))
  cl$shutdown()
  expect_true(inherits(future::plan("next"), "sequential"))
})

test_that("future_lapply() reports a worker error instead of hanging", {
  # Regression: after the first error future.apply cancel()s the remaining
  # futures; resolved() never returned TRUE for "canceled", so result()
  # polled forever.
  skip_if_not_installed("future.apply")
  aws <- local_fake_aws()
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)

  capture.output(future::plan(starburst, workers = 2, instance_type = "c7g.xlarge"))
  expect_error(
    suppressMessages(future.apply::future_lapply(1:3, function(i) stop("every-task-fails"))),
    "every-task-fails"
  )
})
