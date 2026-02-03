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

      # Return mock tasks
      lapply(tasks, function(arn) {
        list(
          startedAt = as.numeric(Sys.time()) - 3600,
          stoppedAt = as.numeric(Sys.time())
        )
      })
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
