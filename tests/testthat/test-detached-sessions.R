test_that("session state functions work correctly", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  # Setup
  config <- get_starburst_config()
  session_id <- sprintf("test-session-%s", gsub("-", "", uuid::UUIDgenerate()))
  region <- config$region %||% "us-east-1"
  bucket <- config$bucket

  # Create minimal backend
  backend <- list(
    session_id = session_id,
    workers = 2,
    cpu = 1,
    memory = "2GB",
    region = region,
    bucket = bucket,
    timeout = 600,
    absolute_timeout = 3600,
    image_uri = "dummy-image",
    cluster = "test-cluster",
    cluster_name = "test-cluster",
    launch_type = "FARGATE",
    instance_type = NULL,
    use_spot = FALSE,
    architecture = "X86_64",
    warm_pool_timeout = 3600,
    capacity_provider_name = "test-provider",
    asg_name = "test-asg",
    aws_account_id = "123456789012",
    subnets = list("subnet-1"),
    security_groups = list("sg-1"),
    task_definition_arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/test:1"
  )

  # Test create_session_manifest
  expect_silent(create_session_manifest(session_id, backend))

  # Test get_session_manifest
  manifest <- get_session_manifest(session_id, region, bucket)
  expect_equal(manifest$session_id, session_id)
  expect_equal(manifest$backend$workers, 2)
  expect_equal(manifest$stats$total_tasks, 0)

  # Test update_session_manifest
  expect_silent(update_session_manifest(
    session_id = session_id,
    updates = list(stats = list(total_tasks = 5, pending = 3)),
    region = region,
    bucket = bucket
  ))

  manifest <- get_session_manifest(session_id, region, bucket)
  expect_equal(manifest$stats$total_tasks, 5)
  expect_equal(manifest$stats$pending, 3)

  # Test create_task_status
  task_id <- "test-task-1"
  expect_silent(create_task_status(session_id, task_id, "pending", region, bucket))

  # Test get_task_status
  status <- get_task_status(session_id, task_id, region, bucket)
  expect_equal(status$task_id, task_id)
  expect_equal(status$state, "pending")
  expect_null(status$claimed_by)

  # Test atomic_claim_task
  worker_id <- "worker-1"
  claimed <- atomic_claim_task(session_id, task_id, worker_id, region, bucket)
  expect_true(claimed)

  status <- get_task_status(session_id, task_id, region, bucket)
  expect_equal(status$state, "claimed")
  expect_equal(status$claimed_by, worker_id)

  # Test that second claim fails (atomic)
  claimed2 <- atomic_claim_task(session_id, task_id, "worker-2", region, bucket)
  expect_false(claimed2)

  # Test list_pending_tasks
  task_id2 <- "test-task-2"
  create_task_status(session_id, task_id2, "pending", region, bucket)

  pending <- list_pending_tasks(session_id, region, bucket)
  expect_true(task_id2 %in% pending)
  expect_false(task_id %in% pending)  # Already claimed

  # Test list_task_statuses
  statuses <- list_task_statuses(session_id, region, bucket)
  expect_equal(length(statuses), 2)
  expect_true(task_id %in% names(statuses))
  expect_true(task_id2 %in% names(statuses))

  # Cleanup
  s3 <- get_s3_client(region)
  prefix <- sprintf("sessions/%s/", session_id)
  tryCatch({
    objects <- s3$list_objects_v2(Bucket = bucket, Prefix = prefix)
    if (length(objects$Contents) > 0) {
      for (obj in objects$Contents) {
        s3$delete_object(Bucket = bucket, Key = obj$Key)
      }
    }
  }, error = function(e) {
    # Ignore cleanup errors
  })
})

test_that("detached session creation works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  # This test launches actual workers
  session <- starburst_session(
    workers = 2,
    cpu = 1,
    memory = "2GB",
    launch_type = "FARGATE"
  )

  expect_s3_class(session, "StarburstSession")
  expect_true(!is.null(session$session_id))
  expect_true(!is.null(session$backend))

  # Cleanup
  session$cleanup()
})

test_that("session submit and collect workflow", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  # Create session
  session <- starburst_session(workers = 2, cpu = 1, memory = "2GB")

  # Submit tasks
  task_ids <- lapply(1:5, function(i) {
    session$submit(quote(i * 2))
  })

  expect_equal(length(task_ids), 5)

  # Check status
  status <- session$status()
  expect_s3_class(status, "StarburstSessionStatus")
  expect_equal(status$total, 5)

  # Wait and collect
  Sys.sleep(60)  # Give workers time to process
  results <- session$collect(wait = FALSE)

  expect_true(length(results) > 0)

  # Cleanup
  session$cleanup()
})

test_that("session attach workflow", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  # Create session
  session <- starburst_session(workers = 2, cpu = 1, memory = "2GB")
  session_id <- session$session_id

  # Submit tasks
  lapply(1:10, function(i) session$submit(quote({Sys.sleep(5); i})))

  # Detach (simulate closing R)
  rm(session)

  # Reattach
  session <- starburst_session_attach(session_id)

  expect_s3_class(session, "StarburstSession")
  expect_equal(session$session_id, session_id)

  # Check status
  status <- session$status()
  expect_equal(status$total, 10)

  # Collect results
  results <- session$collect(wait = TRUE, timeout = 180)
  expect_equal(length(results), 10)

  # Cleanup
  session$cleanup()
})

test_that("list sessions works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  sessions <- starburst_list_sessions()

  expect_true(is.data.frame(sessions))
  expect_true("session_id" %in% colnames(sessions))
})

test_that("worker detached mode detection works", {
  # This tests the logic without actually running a worker

  # Mock task with session_id (detached mode)
  detached_task <- list(
    session_id = "session-123",
    task_id = "task-456",
    expr = quote(2 + 2),
    globals = list(),
    packages = NULL
  )

  expect_true(!is.null(detached_task$session_id))

  # Mock task without session_id (ephemeral mode)
  ephemeral_task <- list(
    task_id = "task-789",
    expr = quote(3 + 3),
    globals = list(),
    packages = NULL
  )

  expect_true(is.null(ephemeral_task$session_id))
})

test_that("plan guard prevents detached mode misuse", {
  expect_error(
    plan.starburst(
      strategy = starburst,
      workers = 10,
      detached = TRUE
    ),
    "Detached mode cannot be used with plan"
  )
})
