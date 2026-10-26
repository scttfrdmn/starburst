# Offline regressions for the future-backend paths that were broken on real
# AWS since v0.3.0 but invisible to the (mocked) suite: #63, #64, #65.

# A strategy shaped like the one plan.starburst() returns: tweaked `starburst`
# (which keeps its StarburstBackend factory) plus a pre-built backend and
# init = TRUE. future::plan() rejects this shape (#64).
fake_plan_starburst <- function(backend) {
  function(...) {
    strategy <- future::tweak(starburst, workers = 2)
    attr(strategy, "backend") <- backend
    attr(strategy, "init") <- TRUE
    strategy
  }
}

# Wrap the real constructor, record the backend each future was given, and
# resolve it locally so run()/resolved()/result() never touch AWS.
local_resolving_futures <- function(seen, env = parent.frame()) {
  real <- StarburstFuture
  testthat::local_mocked_bindings(
    StarburstFuture = function(...) {
      f <- real(...)
      seen$backends <- c(seen$backends, list(f$backend))
      value <- eval(f$expr, envir = list2env(as.list(f$globals)))
      f$state <- "finished"
      f$result_value <- future::FutureResult(value = value, conditions = list())
      f
    },
    .env = env
  )
}

test_that("starburst_map runs without registering a plan and uses its own backend (#64)", {
  backend <- new.env()
  seen <- new.env()
  local_mocked_bindings(
    plan.starburst = fake_plan_starburst(backend),
    get_starburst_config = function() list(region = "us-east-1")
  )
  local_resolving_futures(seen)

  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)

  res <- starburst_map(1:3, function(x) x * 10, workers = 2, .progress = FALSE)

  expect_equal(res, list(10, 20, 30))
  expect_length(seen$backends, 3)
  expect_true(all(vapply(seen$backends, identical, logical(1), backend)))
  expect_true(inherits(future::plan("next"), "sequential"))
})

test_that("starburst_cluster creates a cluster without registering a plan (#64)", {
  backend <- new.env()
  backend$cluster_id <- "starburst-test"
  backend$workers <- 2
  seen <- new.env()
  local_mocked_bindings(
    plan.starburst = fake_plan_starburst(backend),
    get_starburst_config = function() list(region = "us-east-1")
  )
  local_resolving_futures(seen)

  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)

  cluster <- starburst_cluster(workers = 2)
  expect_identical(cluster$backend, backend)
  expect_true(inherits(future::plan("next"), "sequential"))

  res <- cluster$map(1:2, function(x) x + 1, .progress = FALSE)
  expect_equal(res, list(2, 3))
  expect_true(all(vapply(seen$backends, identical, logical(1), backend)))
})

test_that("the plan.starburst() strategy shape is what future::plan() rejects (#64)", {
  # Documents why starburst_map()/starburst_cluster() must not register it.
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)
  strategy <- fake_plan_starburst(new.env())()
  expect_error(future::plan(strategy), "did not shut itself down properly")
})

# A future as plan(starburst) produces it: future() builds a regular Future
# and launchFuture.StarburstBackend() adds the StarburstFuture class.
launched_future <- function(result_data) {
  testthat::local_mocked_bindings(
    get_s3_client = function(...) list(
      download_file = function(Bucket, Key, Filename) qs2::qs_save(result_data, Filename)
    ),
    .env = parent.frame()
  )
  f <- future::Future(quote(1), substitute = FALSE, globals = FALSE, lazy = TRUE)
  f$task_id <- "task-test"
  f$backend <- list2env(list(region = "us-east-1", bucket = "b"))
  class(f) <- c("StarburstFuture", class(f))
  f$state <- "finished"
  f
}

test_that("worker errors reach value() with their message, not INTERNAL ERROR (#65)", {
  skip_if_not_installed("qs2")
  f <- launched_future(list(error = TRUE, message = "boom from worker"))

  res <- future::result(f)
  expect_s3_class(res, "FutureResult")
  expect_s3_class(res$conditions[[1]]$condition, "error")
  expect_error(future::value(f), "boom from worker")
})

test_that("successful worker results reach value() (#65)", {
  skip_if_not_installed("qs2")
  f <- launched_future(list(error = FALSE, value = 42))

  expect_equal(future::value(f), 42)
})

test_that("starburst_map surfaces worker error messages (#65)", {
  skip_if_not_installed("qs2")
  local_mocked_bindings(
    plan.starburst = fake_plan_starburst(new.env()),
    get_starburst_config = function() list(region = "us-east-1")
  )
  real <- StarburstFuture
  local_mocked_bindings(StarburstFuture = function(...) {
    f <- real(...)
    f$state <- "finished"
    f
  })
  local_mocked_bindings(get_s3_client = function(...) list(
    download_file = function(Bucket, Key, Filename) {
      qs2::qs_save(list(error = TRUE, message = "boom from worker"), Filename)
    }
  ))

  expect_error(starburst_map(1:2, identity, workers = 2, .progress = FALSE),
               "Task 1 failed: boom from worker")
})

test_that("ephemeral worker uploads under the TASK_ID it was started with (#63)", {
  worker <- system.file("templates", "worker.R", package = "starburst")
  skip_if(!nzchar(worker), "worker template not installed")

  env <- new.env()
  src <- readLines(worker, warn = FALSE)
  eval(parse(text = src[!grepl("^main\\(\\)\\s*$", src)]), envir = env)

  uploaded_as <- NULL
  env$upload_result <- function(result, task_id, s3, bucket) {
    uploaded_as <<- task_id
  }
  env$quit <- function(...) invisible(NULL)
  env$message <- function(...) invisible(NULL)

  # Same fields as the payload run.StarburstFuture()/launchFuture() upload:
  # no task_id, so the key must come from the env var passed in by main().
  task <- list(expr = quote(1 + 1), globals = list(), packages = NULL, seed = FALSE)
  env$run_ephemeral_worker(task, s3 = NULL, bucket = "b", region = "us-east-1",
                           task_id = "task-abc")

  expect_identical(uploaded_as, "task-abc")
})

test_that("plan.starburst() backend has the fields StarburstBackend() sets", {
  # Regression: it lacked cluster_name/subnets/security_groups, so
  # start_warm_pool() polled the *default* ECS cluster and starburst_map()/
  # starburst_cluster() timed out with the pool already in service.
  old <- options(starburst.cleanup_handlers = NULL,
                 starburst.current_backend = NULL,
                 starburst.current_cluster_id = NULL)
  on.exit(options(old), add = TRUE)
  local_mocked_bindings(
    get_starburst_config = function() list(
      region = "us-east-1", bucket = "b", cluster_name = "starburst-cluster",
      subnets = list("subnet-1"), security_groups = list("sg-1"),
      aws_account_id = "123"
    ),
    check_aws_credentials = function() TRUE,
    ensure_environment = function(...) list(cluster = "c", hash = "h", image_uri = "u"),
    estimate_cost = function(...) list(hourly_rate = 0.1, per_hour = 0.1, total_estimate = 0.1)
  )

  suppressWarnings(capture.output(
    s <- plan.starburst(strategy = starburst, workers = 2,
                        instance_type = "c7g.xlarge", use_spot = FALSE)
  ))
  backend <- attr(s, "backend")
  capture.output(core <- StarburstBackend(workers = 2, instance_type = "c7g.xlarge"))

  expect_identical(backend$cluster_name, "starburst-cluster")
  expect_identical(backend$subnets, list("subnet-1"))
  expect_identical(backend$security_groups, list("sg-1"))
  expect_true(all(names(as.list(attr(core, "backend"))) %in% names(as.list(backend))))
})

test_that("submit_task() sends EC2-valid run_task parameters", {
  # Regression: it always set assignPublicIp, which EC2 run_task rejects
  # ("Assign public IP is not supported for this launch type"), and ignored
  # the configured subnets/security groups/cluster.
  captured <- NULL
  local_mocked_bindings(
    get_ecs_client = function(...) list(run_task = function(...) {
      captured <<- list(...)
      list(tasks = list(list(taskArn = "arn:task")))
    }),
    get_vpc_config = function(...) stop("should use the configured network"),
    store_task_arn = function(...) invisible(NULL)
  )
  make_backend <- function(launch_type) list2env(list(
    launch_type = launch_type, region = "us-east-1", bucket = "b",
    cluster = "fallback-cluster", cluster_name = "starburst-cluster",
    cluster_id = "starburst-x", task_definition_arn = "arn:td",
    pool_started_at = Sys.time(), capacity_provider_name = "starburst-c7g-xlarge",
    instance_type = "c7g.xlarge",
    subnets = list("subnet-1"), security_groups = list("sg-1")
  ))
  f <- new.env()
  f$task_id <- "task-1"

  submit_task(f, make_backend("EC2"))
  vpc <- captured$networkConfiguration$awsvpcConfiguration
  expect_null(vpc$assignPublicIp)
  expect_identical(vpc$subnets, list("subnet-1"))
  expect_identical(vpc$securityGroups, list("sg-1"))
  expect_identical(captured$cluster, "starburst-cluster")
  expect_null(captured$launchType)
  expect_identical(f$state, "running")

  submit_task(f, make_backend("FARGATE"))
  expect_identical(captured$networkConfiguration$awsvpcConfiguration$assignPublicIp, "ENABLED")
  expect_identical(captured$launchType, "FARGATE")
})

test_that("a canceled future without a result is resolved and signals cancellation", {
  local_mocked_bindings(get_s3_client = function(...) list(
    head_object = function(...) stop("NotFound (HTTP 404)"),
    download_file = function(...) stop("NotFound (HTTP 404)")
  ))
  backend <- list2env(list(region = "us-east-1", bucket = "b"))
  f <- StarburstFuture(quote(1), substitute = FALSE, globals = FALSE, backend = backend)
  f$state <- "canceled"

  expect_true(resolved(f))
  res <- result(f)
  expect_s3_class(res$conditions[[1]]$condition, "FutureCanceledError")
})
