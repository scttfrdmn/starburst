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
  local_time_limit(60)
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

# --- Dead workers (#67) ------------------------------------------------------

test_that("value() fails with the ECS reason when a worker dies without a result", {
  local_time_limit(60)
  aws <- local_fake_aws()
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)
  capture.output(future::plan(starburst, workers = 2, instance_type = "c7g.xlarge"))

  aws$ecs$calls$mode <- "die"
  err <- tryCatch(future::value(future::future(1 + 1)), error = identity)
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "stopped without returning a result")
  expect_match(conditionMessage(err), "OutOfMemoryError")
})

test_that("starburst_map() fails instead of hanging when a worker dies", {
  local_time_limit(60)
  aws <- local_fake_aws()
  aws$ecs$calls$mode <- "die"
  capture.output(
    err <- tryCatch(starburst_map(1:2, function(x) x, workers = 2,
                                  instance_type = "c7g.xlarge", .progress = FALSE),
                    error = identity)
  )
  expect_match(conditionMessage(err), "stopped without returning a result")
})

test_that("a task that never finishes is stopped at its timeout", {
  local_time_limit(60)
  aws <- local_fake_aws()
  withr::local_options(starburst.task_start_margin = 0)
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)
  capture.output(future::plan(starburst, workers = 2, instance_type = "c7g.xlarge",
                              timeout = 1))

  aws$ecs$calls$mode <- "hang"
  f <- future::future(1)
  Sys.sleep(1.5)
  err <- tryCatch(future::value(f), error = identity)
  expect_match(conditionMessage(err), "did not finish within its timeout")
  expect_length(aws$ecs$calls$stopped, 1)
})

# --- Warm pool lifecycle and cleanup scope (#59) -----------------------------

test_that("warm_pool_timeout holds the pool, with its release always scheduled", {
  aws <- local_fake_aws()
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)
  capture.output(future::plan(starburst, workers = 2, instance_type = "c7g.xlarge",
                              warm_pool_timeout = 600))
  expect_equal(future::value(future::future(3)), 3)
  expect_equal(aws$autoscaling$asg$desired, 2)
  # Held while the plan is active too, so idle gaps between runs don't drain it,
  # and a release is always pending in case R never gets to plan(sequential)
  expect_equal(aws$autoscaling$asg$min, 2)
  expect_false(is.null(aws$autoscaling$asg$actions[["starburst-release-warm-pool"]]))

  # A future still running when the plan ends is stopped by stopWorkers()
  aws$ecs$calls$mode <- "hang"
  unfinished <- future::future(4)
  # stopWorkers() must be implemented: no "does not implement stopWorkers()"
  expect_no_warning(capture.output(future::plan(future::sequential)))
  expect_true(unfinished$task_arn %in% aws$ecs$calls$stopped)

  asg <- aws$autoscaling$asg
  expect_equal(asg$min, 2)                       # held warm
  action <- asg$actions[["starburst-release-warm-pool"]]
  expect_false(is.null(action))                  # and released by AWS later
  expect_equal(action$min, 0)
  expect_gt(as.numeric(difftime(action$start, Sys.time(), units = "secs")), 500)
})

test_that("starburst_map() takes over a held pool and releases it when done", {
  aws <- local_fake_aws()
  asg <- aws$autoscaling$asg
  # Pool held warm by an earlier plan, with its release pending
  asg$min <- 3L; asg$desired <- 3L
  asg$actions[["starburst-release-warm-pool"]] <- list(start = Sys.time() + 3600, min = 0L)

  capture.output(res <- starburst_map(1:2, function(x) x * 2, workers = 2,
                                      instance_type = "c7g.xlarge", .progress = FALSE))
  expect_equal(res, list(2, 4))
  expect_equal(asg$min, 0)
  expect_equal(asg$desired, 0)
  expect_null(asg$actions[["starburst-release-warm-pool"]])
})

test_that("cleanup only stops this run's tasks and deletes its S3 objects", {
  aws <- local_fake_aws()
  # Someone else's detached-session worker in the shared cluster
  foreign <- "arn:aws:ecs:task/session-other-task-1"
  assign(foreign, list(taskArn = foreign, lastStatus = "RUNNING"), envir = aws$ecs$tasks)

  capture.output(cl <- starburst_cluster(workers = 2, instance_type = "c7g.xlarge"))
  capture.output(res <- cl$map(1:2, function(x) x, .progress = FALSE))
  capture.output(cl$shutdown())

  expect_false(foreign %in% aws$ecs$calls$stopped)
  keys <- ls(aws$s3$store)
  expect_length(keys[grepl("^(tasks|results)/", keys)], 0)
  # The foreign task is still running, so the pool is left to drain, not cut
  expect_equal(aws$autoscaling$asg$min, 0)
})
