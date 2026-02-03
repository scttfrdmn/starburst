test_that("list_active_clusters returns empty list when no tasks", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock ECS client
  ecs_client <- list(
    list_tasks = function(...) {
      list(taskArns = list())
    }
  )

  mockery::stub(list_active_clusters, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- list_active_clusters("us-east-1")

  expect_type(result, "list")
  expect_length(result, 0)
})

test_that("list_active_clusters groups tasks by cluster ID", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock ECS client
  ecs_client <- list(
    list_tasks = function(...) {
      list(
        taskArns = list(
          "arn:task-1",
          "arn:task-2",
          "arn:task-3"
        )
      )
    },
    describe_tasks = function(...) {
      list(
        tasks = list(
          list(
            taskArn = "arn:task-1",
            startedAt = as.numeric(Sys.time()),
            lastStatus = "RUNNING",
            overrides = list(
              containerOverrides = list(
                list(
                  environment = list(
                    list(name = "CLUSTER_ID", value = "cluster-A")
                  )
                )
              )
            )
          ),
          list(
            taskArn = "arn:task-2",
            startedAt = as.numeric(Sys.time()),
            lastStatus = "RUNNING",
            overrides = list(
              containerOverrides = list(
                list(
                  environment = list(
                    list(name = "CLUSTER_ID", value = "cluster-A")
                  )
                )
              )
            )
          ),
          list(
            taskArn = "arn:task-3",
            startedAt = as.numeric(Sys.time()),
            lastStatus = "RUNNING",
            overrides = list(
              containerOverrides = list(
                list(
                  environment = list(
                    list(name = "CLUSTER_ID", value = "cluster-B")
                  )
                )
              )
            )
          )
        )
      )
    }
  )

  mockery::stub(list_active_clusters, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- list_active_clusters("us-east-1")

  expect_length(result, 2)
  expect_true("cluster-A" %in% names(result))
  expect_true("cluster-B" %in% names(result))

  expect_equal(result[["cluster-A"]]$task_count, 2)
  expect_equal(result[["cluster-B"]]$task_count, 1)
})

test_that("list_active_clusters handles tasks without cluster ID", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock ECS client
  ecs_client <- list(
    list_tasks = function(...) {
      list(taskArns = list("arn:task-1"))
    },
    describe_tasks = function(...) {
      list(
        tasks = list(
          list(
            taskArn = "arn:task-1",
            startedAt = as.numeric(Sys.time()),
            lastStatus = "RUNNING",
            overrides = list(
              containerOverrides = list(
                list(
                  environment = list()  # No CLUSTER_ID
                )
              )
            )
          )
        )
      )
    }
  )

  mockery::stub(list_active_clusters, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- list_active_clusters("us-east-1")

  # Should return empty list (no cluster ID found)
  expect_length(result, 0)
})

test_that("list_active_clusters handles ECS errors gracefully", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock ECS client that throws error
  ecs_client <- list(
    list_tasks = function(...) {
      stop("ClusterNotFoundException")
    }
  )

  mockery::stub(list_active_clusters, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- list_active_clusters("us-east-1")

  expect_type(result, "list")
  expect_length(result, 0)
})

test_that("list_active_clusters includes task details", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  start_time <- as.numeric(Sys.time())

  # Mock ECS client
  ecs_client <- list(
    list_tasks = function(...) {
      list(taskArns = list("arn:task-1"))
    },
    describe_tasks = function(...) {
      list(
        tasks = list(
          list(
            taskArn = "arn:task-1",
            startedAt = start_time,
            lastStatus = "RUNNING",
            overrides = list(
              containerOverrides = list(
                list(
                  environment = list(
                    list(name = "CLUSTER_ID", value = "test-cluster")
                  )
                )
              )
            )
          )
        )
      )
    }
  )

  mockery::stub(list_active_clusters, "get_ecs_client", function(...) {
    ecs_client
  })

  result <- list_active_clusters("us-east-1")

  cluster <- result[["test-cluster"]]
  expect_equal(cluster$cluster_id, "test-cluster")
  expect_equal(cluster$task_count, 1)
  expect_length(cluster$tasks, 1)

  task <- cluster$tasks[[1]]
  expect_equal(task$task_arn, "arn:task-1")
  expect_equal(task$started_at, start_time)
  expect_equal(task$status, "RUNNING")
})
