#!/usr/bin/env Rscript
# Direct AWS Infrastructure Test
# Tests Docker build, ECR push, ECS task creation without future integration

library(starburst)

cat("Direct AWS Infrastructure Test\n")
cat("==============================\n\n")

# Test 1: Configuration
cat("1. Checking configuration...\n")
config <- starburst:::get_starburst_config()
cat(sprintf("   Region: %s\n", config$region))
cat(sprintf("   Bucket: %s\n", config$bucket))
cat(sprintf("   Setup complete: %s\n\n", config$setup_complete))

# Test 2: Docker image build and ECR push
cat("2. Building and pushing Docker image...\n")
env_info <- starburst:::ensure_environment(config$region)
cat(sprintf("   Image URI: %s\n", env_info$image_uri))
cat(sprintf("   Hash: %s\n\n", env_info$hash))

# Test 3: Task definition
cat("3. Creating task definition...\n")
task_def_arn <- starburst:::get_or_create_task_definition(
  cpu = 4,
  memory = 8192,
  image_uri = env_info$image_uri,
  region = config$region,
  cluster_id = "test-cluster"
)
cat(sprintf("   Task definition: %s\n\n", task_def_arn))

# Test 4: Create simple task
cat("4. Creating test task...\n")
test_expr <- quote({
  # Simple computation
  x <- 1:1000
  sum(x^2)
})

task_id <- sprintf("test-%s", gsub("-", "", uuid::UUIDgenerate()))
s3 <- starburst:::get_s3_client(config$region)

# Serialize task to S3
task_data <- list(
  expr = test_expr,
  globals = list(),
  packages = NULL
)
task_key <- sprintf("tasks/%s.qs", task_id)
temp_file <- tempfile(fileext = ".qs")
qs::qsave(task_data, temp_file)

s3$put_object(
  Bucket = config$bucket,
  Key = task_key,
  Body = temp_file
)

cat(sprintf("   Task uploaded: s3://%s/%s\n", config$bucket, task_key))

# Test 5: Submit ECS task
cat("\n5. Submitting ECS task...\n")
ecs <- starburst:::get_ecs_client(config$region)

# Get network configuration
vpc_config <- starburst:::get_vpc_config(config$region)

response <- ecs$run_task(
  cluster = "default",
  taskDefinition = task_def_arn,
  launchType = "FARGATE",
  networkConfiguration = list(
    awsvpcConfiguration = list(
      subnets = vpc_config$subnets,
      securityGroups = vpc_config$security_groups,
      assignPublicIp = "ENABLED"
    )
  ),
  overrides = list(
    containerOverrides = list(
      list(
        name = "starburst-worker",
        environment = list(
          list(name = "TASK_ID", value = task_id),
          list(name = "S3_BUCKET", value = config$bucket),
          list(name = "AWS_DEFAULT_REGION", value = config$region),
          list(name = "CLUSTER_ID", value = "test-cluster")
        )
      )
    )
  )
)

if (length(response$tasks) > 0) {
  task_arn <- response$tasks[[1]]$taskArn
  cat(sprintf("   Task ARN: %s\n", task_arn))
  cat(sprintf("   Status: %s\n", response$tasks[[1]]$lastStatus))

  # Test 6: Poll for result
  cat("\n6. Waiting for result (max 2 minutes)...\n")
  result_key <- sprintf("results/%s.qs", task_id)

  start_time <- Sys.time()
  result <- NULL
  while (difftime(Sys.time(), start_time, units = "secs") < 120) {
    tryCatch({
      temp_result <- tempfile(fileext = ".qs")
      s3$download_file(
        Bucket = config$bucket,
        Key = result_key,
        Filename = temp_result
      )
      result <- qs::qread(temp_result)
      unlink(temp_result)
      break
    }, error = function(e) {
      Sys.sleep(5)
    })
  }

  if (!is.null(result)) {
    cat("   ✓ Task completed successfully!\n")
    cat(sprintf("   Result: %s\n", result$value))
  } else {
    cat("   ✗ Task did not complete within 2 minutes\n")
    cat("   Checking task status...\n")
    task_info <- ecs$describe_tasks(
      cluster = "default",
      tasks = list(task_arn)
    )
    if (length(task_info$tasks) > 0) {
      cat(sprintf("   Last status: %s\n", task_info$tasks[[1]]$lastStatus))
      if (!is.null(task_info$tasks[[1]]$stoppedReason)) {
        cat(sprintf("   Stopped reason: %s\n", task_info$tasks[[1]]$stoppedReason))
      }
    }
  }
} else {
  cat("   ✗ Failed to start ECS task\n")
  if (length(response$failures) > 0) {
    cat(sprintf("   Failure: %s - %s\n",
                response$failures[[1]]$reason,
                response$failures[[1]]$detail))
  }
}

cat("\nTest complete!\n")
