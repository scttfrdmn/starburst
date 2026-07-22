test_that("calculate_total_cost handles empty task list", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  plan <- list(
    region = "us-east-1",
    worker_cpu = 2,
    worker_memory = 8
  )

  # Mock list_task_arns to return empty
  mockery::stub(calculate_total_cost, "list_task_arns", function() {
    list()
  })

  result <- calculate_total_cost(plan)
  expect_equal(result, 0)
})

test_that("calculate_total_cost calculates from actual task runtimes", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  plan <- list(
    region = "us-east-1",
    worker_cpu = 2,    # 2 vCPUs
    worker_memory = 8  # 8 GB
  )

  # Mock list_task_arns
  mockery::stub(calculate_total_cost, "list_task_arns", function() {
    list(
      "task-1" = list(task_arn = "arn:task-1"),
      "task-2" = list(task_arn = "arn:task-2")
    )
  })

  # Mock ECS client
  ecs_client <- list(
    describe_tasks = function(...) {
      # Task ran for 1 hour
      start_time <- as.numeric(Sys.time()) - 3600
      stop_time <- as.numeric(Sys.time())

      list(
        tasks = list(
          list(
            startedAt = start_time,
            stoppedAt = stop_time
          ),
          list(
            startedAt = start_time,
            stoppedAt = stop_time
          )
        )
      )
    }
  )

  mockery::stub(calculate_total_cost, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- calculate_total_cost(plan)

  # Expected cost for 2 tasks, each running 1 hour:
  # vCPU cost: 2 vCPU * $0.04048/vCPU-hour * 1 hour * 2 tasks = $0.16192
  # Memory cost: 8 GB * $0.004445/GB-hour * 1 hour * 2 tasks = $0.07112
  # Total: $0.23304
  expect_gt(result, 0.2)
  expect_lt(result, 0.3)
})

test_that("calculate_total_cost handles running tasks", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  plan <- list(
    region = "us-east-1",
    worker_cpu = 1,
    worker_memory = 2
  )

  # Mock list_task_arns
  mockery::stub(calculate_total_cost, "list_task_arns", function() {
    list("task-1" = list(task_arn = "arn:task-1"))
  })

  # Mock ECS client - task still running (no stoppedAt)
  ecs_client <- list(
    describe_tasks = function(...) {
      start_time <- as.numeric(Sys.time()) - 1800  # Started 30 min ago

      list(
        tasks = list(
          list(
            startedAt = start_time,
            stoppedAt = NULL  # Still running
          )
        )
      )
    }
  )

  mockery::stub(calculate_total_cost, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- calculate_total_cost(plan)

  # Should calculate cost from start time to now
  expect_gt(result, 0)
})

test_that("calculate_total_cost handles batches of tasks", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  plan <- list(
    region = "us-east-1",
    worker_cpu = 1,
    worker_memory = 2
  )

  # Create 150 tasks (more than batch size of 100)
  task_list <- list()
  for (i in 1:150) {
    task_list[[paste0("task-", i)]] <- list(task_arn = paste0("arn:task-", i))
  }

  mockery::stub(calculate_total_cost, "list_task_arns", function() {
    task_list
  })

  batch_count <- 0

  # Mock ECS client
  ecs_client <- list(
    describe_tasks = function(cluster, tasks) {
      batch_count <<- batch_count + 1

      # Return mock tasks in correct format
      list(tasks = lapply(tasks, function(arn) {
        list(
          startedAt = as.numeric(Sys.time()) - 3600,
          stoppedAt = as.numeric(Sys.time())
        )
      }))
    }
  )

  mockery::stub(calculate_total_cost, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- calculate_total_cost(plan)

  # Should make 2 batches (100 + 50)
  expect_equal(batch_count, 2)
  expect_gt(result, 0)
})

test_that("calculate_total_cost falls back to plan cost on error", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  plan <- list(
    region = "us-east-1",
    worker_cpu = 2,
    worker_memory = 8,
    total_cost = 1.5  # Fallback value
  )

  # Mock list_task_arns to throw error
  mockery::stub(calculate_total_cost, "list_task_arns", function() {
    stop("AWS error")
  })

  result <- calculate_total_cost(plan)

  expect_equal(result, 1.5)
})

test_that("estimate_cost returns a normalized hourly_rate for every backend", {
  fg <- estimate_cost(10, 4, "8GB", launch_type = "FARGATE")
  expect_true(!is.null(fg$hourly_rate) && fg$hourly_rate > 0)
  expect_equal(fg$hourly_rate, fg$per_hour)  # back-compat field agrees

  # EC2 On-Demand and Spot both expose hourly_rate (== total_per_hour)
  ec2_od <- estimate_cost(10, 4, "8GB", launch_type = "EC2",
                          instance_type = "c7g.xlarge", use_spot = FALSE)
  expect_true(!is.null(ec2_od$hourly_rate) && ec2_od$hourly_rate > 0)
  expect_equal(ec2_od$hourly_rate, ec2_od$total_per_hour)

  ec2_spot <- estimate_cost(10, 4, "8GB", launch_type = "EC2",
                            instance_type = "c7g.xlarge", use_spot = TRUE)
  expect_true(!is.null(ec2_spot$hourly_rate) && ec2_spot$hourly_rate > 0)
  # spot should be cheaper than on-demand for the same shape
  expect_lt(ec2_spot$hourly_rate, ec2_od$hourly_rate)
})

test_that("max_hourly_cost guard fires on the EC2 default path (regression)", {
  skip_if_not_installed("mockery")

  # Regression: the guard read cost_est$per_hour, which is NULL on EC2, so the
  # limit was silently unenforced on the default backend. It must STOP now.
  mockery::stub(plan.starburst, "get_starburst_config",
                function() list(region = "us-east-1", max_hourly_cost = 0.01))
  mockery::stub(plan.starburst, "check_aws_credentials", function() TRUE)
  mockery::stub(plan.starburst, "check_ecr_image_exists", function(...) TRUE)

  expect_error(
    plan.starburst(strategy = starburst, workers = 50, cpu = 4,
                   launch_type = "EC2", instance_type = "c7g.xlarge",
                   use_spot = FALSE),
    "exceeds limit"
  )
})

test_that("cost_alert_threshold warns but does NOT stop the plan", {
  skip_if_not_installed("mockery")

  # Alert threshold below the estimate, and NO max_hourly_cost, so the only thing
  # that could halt on cost is the alert — which must warn, not stop. We let the
  # plan proceed past the cost checks and throw a sentinel at ensure_environment()
  # to prove execution continued past the alert.
  mockery::stub(plan.starburst, "get_starburst_config",
                function() list(region = "us-east-1", cost_alert_threshold = 0.01))
  mockery::stub(plan.starburst, "check_aws_credentials", function() TRUE)
  mockery::stub(plan.starburst, "ensure_environment",
                function(...) stop("SENTINEL: reached environment setup"))

  out <- capture.output(
    err <- tryCatch(
      plan.starburst(strategy = starburst, workers = 50, cpu = 4,
                     launch_type = "EC2", instance_type = "c7g.xlarge",
                     use_spot = FALSE),
      error = function(e) conditionMessage(e)
    )
  )

  # It stopped at the sentinel (i.e. it got PAST the alert), not on the alert.
  expect_match(err, "SENTINEL")
  # And the alert warning was emitted.
  expect_match(paste(out, collapse = "\n"), "alert threshold", fixed = TRUE)
})

test_that("get_ec2_instance_price falls back to static rate when live lookup fails", {
  skip_if_not_installed("mockery")

  # Clear any cached value for this key, then force the live lookup to error.
  mockery::stub(get_ec2_instance_price, "get_ec2_ondemand_price",
                function(...) stop("no network"))
  mockery::stub(get_ec2_instance_price, "get_starburst_config",
                function() list(region = "us-east-1"))

  price <- get_ec2_instance_price("c7g.xlarge", use_spot = FALSE, region = "us-east-1")
  # Falls back to the static snapshot value for c7g.xlarge.
  expect_equal(price, .static_ec2_prices()[["c7g.xlarge"]])
})

test_that("get_ec2_instance_price uses the live rate when available", {
  skip_if_not_installed("mockery")

  mockery::stub(get_ec2_instance_price, "get_ec2_ondemand_price", function(...) 0.999)
  mockery::stub(get_ec2_instance_price, "get_starburst_config",
                function() list(region = "us-east-1"))

  # Unique region key avoids the session cache from the previous test.
  price <- get_ec2_instance_price("c7g.xlarge", use_spot = FALSE, region = "eu-west-1")
  expect_equal(price, 0.999)
})
