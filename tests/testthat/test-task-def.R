test_that("ensure_log_group creates log group if missing", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock cloudwatchlogs client
  logs_client <- list(
    describe_log_groups = function(...) {
      stop("ResourceNotFoundException")
    },
    create_log_group = function(...) {
      list()
    }
  )

  mockery::stub(ensure_log_group, "paws.management::cloudwatchlogs", function(...) {
    logs_client
  })

  # Should not error
  expect_error(ensure_log_group("/aws/ecs/test", "us-east-1"), NA)
})

test_that("get_execution_role_arn returns configured role", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  mockery::stub(get_execution_role_arn, "get_starburst_config", function() {
    list(execution_role_arn = "arn:aws:iam::123456789012:role/test-role")
  })

  result <- get_execution_role_arn("us-east-1")
  expect_equal(result, "arn:aws:iam::123456789012:role/test-role")
})

test_that("get_execution_role_arn constructs default ARN", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  mockery::stub(get_execution_role_arn, "get_starburst_config", function() {
    list(aws_account_id = "123456789012")
  })

  result <- get_execution_role_arn("us-east-1")
  expect_equal(result, "arn:aws:iam::123456789012:role/starburstECSExecutionRole")
})

test_that("get_task_role_arn constructs default ARN", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  mockery::stub(get_task_role_arn, "get_starburst_config", function() {
    list(aws_account_id = "123456789012")
  })

  result <- get_task_role_arn("us-east-1")
  expect_equal(result, "arn:aws:iam::123456789012:role/starburstECSTaskRole")
})

test_that("get_or_create_task_definition uses existing compatible task def", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock plan object
  plan <- list(
    region = "us-east-1",
    worker_cpu = 2,
    worker_memory = 8,
    image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/test:latest"
  )

  # Mock ECS client
  ecs_client <- list(
    list_task_definitions = function(...) {
      list(taskDefinitionArns = list("arn:aws:ecs:us-east-1:123456789012:task-definition/test:1"))
    },
    describe_task_definition = function(...) {
      list(
        taskDefinition = list(
          taskDefinitionArn = "arn:aws:ecs:us-east-1:123456789012:task-definition/test:1",
          cpu = "2048",
          memory = "8192",
          requiresCompatibilities = list("FARGATE"),
          containerDefinitions = list(
            list(image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/test:latest")
          )
        )
      )
    }
  )

  mockery::stub(get_or_create_task_definition, "get_ecs_client", function(...) {
    ecs_client
  })

  mockery::stub(get_or_create_task_definition, "get_starburst_config", function() {
    list()
  })

  mockery::stub(get_or_create_task_definition, "ensure_log_group", function(...) {})
  mockery::stub(get_or_create_task_definition, "get_execution_role_arn", function(...) {
    "arn:aws:iam::123456789012:role/exec-role"
  })
  mockery::stub(get_or_create_task_definition, "get_task_role_arn", function(...) {
    "arn:aws:iam::123456789012:role/task-role"
  })

  result <- get_or_create_task_definition(plan)

  expect_equal(result, "arn:aws:ecs:us-east-1:123456789012:task-definition/test:1")
})

test_that("get_or_create_task_definition creates new task def if needed", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock plan object
  plan <- list(
    region = "us-east-1",
    worker_cpu = 2,
    worker_memory = 8,
    image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/test:latest"
  )

  registered <- FALSE

  # Mock ECS client
  ecs_client <- list(
    list_task_definitions = function(...) {
      list(taskDefinitionArns = list())
    },
    register_task_definition = function(...) {
      registered <<- TRUE
      list(
        taskDefinition = list(
          taskDefinitionArn = "arn:aws:ecs:us-east-1:123456789012:task-definition/test:1"
        )
      )
    }
  )

  mockery::stub(get_or_create_task_definition, "get_ecs_client", function(...) {
    ecs_client
  })

  mockery::stub(get_or_create_task_definition, "get_starburst_config", function() {
    list()
  })

  mockery::stub(get_or_create_task_definition, "ensure_log_group", function(...) {})
  mockery::stub(get_or_create_task_definition, "get_execution_role_arn", function(...) {
    "arn:aws:iam::123456789012:role/exec-role"
  })
  mockery::stub(get_or_create_task_definition, "get_task_role_arn", function(...) {
    "arn:aws:iam::123456789012:role/task-role"
  })

  result <- get_or_create_task_definition(plan)

  expect_true(registered)
  expect_equal(result, "arn:aws:ecs:us-east-1:123456789012:task-definition/test:1")
})
