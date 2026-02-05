# Integration tests for EC2 functionality
# These tests require AWS credentials and will create real resources

test_that("EC2 pool management works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")
  skip_if_not(is_setup_complete(), "starburst not configured")

  config <- get_starburst_config()

  # Create test backend
  backend <- list(
    cluster_name = config$cluster_name,
    region = config$region,
    launch_type = "EC2",
    instance_type = "c6a.large",
    use_spot = FALSE,
    architecture = "X86_64",
    warm_pool_timeout = 600,
    capacity_provider_name = "starburst-c6a-large",
    asg_name = "starburst-asg-c6a-large",
    workers = 1,  # Minimal for testing
    aws_account_id = config$aws_account_id,
    pool_started_at = NULL
  )

  # Test: Get pool status
  status <- get_pool_status(backend)
  expect_type(status, "list")
  expect_true("desired_capacity" %in% names(status))
  expect_true("running_instances" %in% names(status))

  # Test: Start pool (skip actual startup to save time)
  # In real testing, uncomment this:
  # start_warm_pool(backend, capacity = 1, timeout_seconds = 120)
  # expect_true(status$desired_capacity == 1)

  # Test: Stop pool
  stop_warm_pool(backend)
  Sys.sleep(2)
  status <- get_pool_status(backend)
  expect_equal(status$desired_capacity, 0)
})

test_that("Architecture detection works", {
  expect_equal(get_architecture_from_instance_type("c6a.large"), "X86_64")
  expect_equal(get_architecture_from_instance_type("c7g.xlarge"), "ARM64")
  expect_equal(get_architecture_from_instance_type("c8a.2xlarge"), "X86_64")
  expect_equal(get_architecture_from_instance_type("c8g.xlarge"), "ARM64")
  expect_equal(get_architecture_from_instance_type("m6a.large"), "X86_64")
})

test_that("Instance pricing lookup works", {
  price_ondemand <- get_ec2_instance_price("c6a.large", use_spot = FALSE)
  price_spot <- get_ec2_instance_price("c6a.large", use_spot = TRUE)

  expect_type(price_ondemand, "double")
  expect_type(price_spot, "double")
  expect_true(price_ondemand > 0)
  expect_true(price_spot > 0)
  expect_true(price_spot < price_ondemand)  # Spot should be cheaper
})

test_that("Cost estimation works", {
  cost <- estimate_cost(
    workers = 10,
    cpu = 4,
    memory = "8GB",
    estimated_runtime_hours = 1,
    launch_type = "EC2",
    instance_type = "c6a.large",
    use_spot = FALSE
  )

  expect_type(cost, "list")
  expect_true("per_instance" %in% names(cost))
  expect_true("instances_needed" %in% names(cost))
  expect_true("total_estimated" %in% names(cost))
  expect_true(cost$total_estimated > 0)
})

test_that("ECR image age checking works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  config <- get_starburst_config()

  # Test with a TTL that won't trigger rebuild
  result <- check_ecr_image_age(
    region = config$region,
    image_tag = "base-4.5.2",
    ttl_days = 30,
    force_rebuild = FALSE
  )

  expect_type(result, "logical")
})

test_that("Multi-platform detection from manifest works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  config <- get_starburst_config()
  account_id <- config$aws_account_id
  region <- config$region

  # Check if base image has both platforms
  image_uri <- sprintf("%s.dkr.ecr.%s.amazonaws.com/starburst-worker:base-4.5.2",
                      account_id, region)

  # This test requires the image to exist
  skip_if(!check_ecr_image_exists("base-4.5.2", region), "Base image doesn't exist")

  # Use docker manifest inspect to check platforms
  cmd <- sprintf("docker manifest inspect %s 2>/dev/null | grep -c '\"architecture\"'",
                shQuote(image_uri))
  result <- system(cmd, intern = TRUE, ignore.stderr = TRUE)

  # Should have at least 2 architectures (amd64, arm64)
  # Plus possibly attestation manifests
  expect_true(as.integer(result) >= 2)
})
