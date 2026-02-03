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
  expect_silent(ensure_log_group("/aws/ecs/test", "us-east-1"))
})

test_that("get_execution_role_arn returns existing role", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock IAM client
  iam_client <- list(
    get_role = function(...) {
      list(Role = list(Arn = "arn:aws:iam::123456789012:role/test-role"))
    }
  )

  mockery::stub(get_execution_role_arn, "paws.management::iam", function(...) {
    iam_client
  })

  mockery::stub(get_execution_role_arn, "get_starburst_config", function() {
    list()
  })

  result <- get_execution_role_arn("us-east-1")
  expect_equal(result, "arn:aws:iam::123456789012:role/test-role")
})

test_that("get_execution_role_arn creates role if missing", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  role_created <- FALSE

  # Mock IAM client
  iam_client <- list(
    get_role = function(...) {
      stop("NoSuchEntity")
    },
    create_role = function(...) {
      role_created <<- TRUE
      list(Role = list(Arn = "arn:aws:iam::123456789012:role/new-role"))
    },
    attach_role_policy = function(...) {
      list()
    }
  )

  mockery::stub(get_execution_role_arn, "paws.management::iam", function(...) {
    iam_client
  })

  mockery::stub(get_execution_role_arn, "get_starburst_config", function() {
    list()
  })

  result <- get_execution_role_arn("us-east-1")

  expect_true(role_created)
  expect_equal(result, "arn:aws:iam::123456789012:role/new-role")
})

test_that("get_task_role_arn includes S3 permissions", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  s3_policy_set <- FALSE

  # Mock IAM client
  iam_client <- list(
    get_role = function(...) {
      stop("NoSuchEntity")
    },
    create_role = function(...) {
      list(Role = list(Arn = "arn:aws:iam::123456789012:role/task-role"))
    },
    put_role_policy = function(...) {
      s3_policy_set <<- TRUE
      list()
    }
  )

  mockery::stub(get_task_role_arn, "paws.management::iam", function(...) {
    iam_client
  })

  mockery::stub(get_task_role_arn, "get_starburst_config", function() {
    list(
      aws_account_id = "123456789012",
      bucket_name = "test-bucket"
    )
  })

  result <- get_task_role_arn("us-east-1")

  expect_true(s3_policy_set)
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
