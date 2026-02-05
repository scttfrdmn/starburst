# End-to-end integration test for EC2
# This test creates a warm pool, runs tasks, and verifies results
# Run manually with: testthat::test_file("tests/testthat/test-ec2-e2e.R")

test_that("EC2 end-to-end workflow works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")
  skip_if_not(is_setup_complete(), "starburst not configured")
  skip("Manual test - runs real EC2 instances")  # Remove this line to run

  library(future)
  library(future.apply)

  # Configure EC2 backend
  plan(starburst,
       workers = 2,
       cpu = 2,
       memory = "4GB",
       launch_type = "EC2",
       instance_type = "c6a.large",
       use_spot = FALSE,
       warm_pool_timeout = 600,
       region = "us-east-1"
  )

  # Test function
  test_fn <- function(x) {
    Sys.sleep(1)  # Simulate work
    list(
      input = x,
      result = x^2,
      platform = Sys.info()[["machine"]],
      hostname = Sys.info()[["nodename"]]
    )
  }

  # Run tasks
  start_time <- Sys.time()
  results <- future_lapply(1:4, test_fn)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # Verify results
  expect_equal(length(results), 4)
  expect_equal(results[[1]]$input, 1)
  expect_equal(results[[1]]$result, 1)
  expect_equal(results[[2]]$result, 4)
  expect_equal(results[[3]]$result, 9)
  expect_equal(results[[4]]$result, 16)

  # All results should be from x86_64 platform (c6a.large)
  platforms <- sapply(results, function(r) r$platform)
  expect_true(all(platforms == "x86_64"))

  # Cleanup
  plan(sequential)

  # Print timing info
  message(sprintf("E2E test completed in %.1f seconds", elapsed))
})

test_that("Spot instances can be configured", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")
  skip_if_not(is_setup_complete(), "starburst not configured")
  skip("Manual test - uses spot instances")  # Remove to run

  library(future)

  # Configure with spot
  plan(starburst,
       workers = 2,
       launch_type = "EC2",
       instance_type = "c6a.large",
       use_spot = TRUE,  # Use spot for cost savings
       region = "us-east-1"
  )

  backend <- plan()[[1]]

  expect_equal(backend$use_spot, TRUE)
  expect_equal(backend$instance_type, "c6a.large")

  plan(sequential)
})

test_that("Multiple instance types can be used", {
  skip_on_cran()
  skip("Manual test - creates multiple capacity providers")

  # Setup EC2 for multiple instance types
  starburst_setup_ec2(
    region = "us-east-1",
    instance_types = c("c6a.large", "m6a.large"),
    force = FALSE
  )

  # Verify capacity providers exist
  ecs <- get_ecs_client("us-east-1")
  providers <- ecs$describe_capacity_providers(
    capacityProviders = list("starburst-c6a-large", "starburst-m6a-large")
  )

  expect_equal(length(providers$capacityProviders), 2)
})

test_that("ARM64 instances work with multi-platform images", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")
  skip("Manual test - uses ARM64 Graviton instances")  # Remove to run

  library(future)
  library(future.apply)

  # Configure ARM64 backend (Graviton)
  plan(starburst,
       workers = 2,
       launch_type = "EC2",
       instance_type = "c7g.xlarge",  # Graviton3
       use_spot = FALSE,
       region = "us-east-1"
  )

  # Test function
  test_fn <- function(x) {
    list(
      result = x * 2,
      platform = Sys.info()[["machine"]]
    )
  }

  # Run task
  results <- future_lapply(1:2, test_fn)

  # Verify ARM64 platform
  platforms <- sapply(results, function(r) r$platform)
  expect_true(all(platforms == "aarch64"))  # ARM64 architecture

  plan(sequential)
})

test_that("Warm pool timeout works", {
  skip_on_cran()
  skip("Manual test - tests timeout behavior")

  config <- get_starburst_config()

  backend <- list(
    cluster_name = config$cluster_name,
    region = config$region,
    launch_type = "EC2",
    instance_type = "c6a.large",
    asg_name = "starburst-asg-c6a-large",
    warm_pool_timeout = 300,  # 5 minutes
    pool_started_at = Sys.time() - 400  # Started 6 min ago
  )

  # Check if pool should scale down
  idle_time <- difftime(Sys.time(), backend$pool_started_at, units = "secs")

  expect_true(idle_time > backend$warm_pool_timeout)

  # In real cleanup, this would trigger scale-down
  # cleanup_cluster(backend)  # Would scale to 0
})

test_that("Cost estimates are accurate", {
  # Test various configurations
  cost1 <- estimate_cost(10, 4, "8GB", 1, "EC2", "c6a.large", FALSE)
  cost2 <- estimate_cost(10, 4, "8GB", 1, "EC2", "c6a.large", TRUE)

  # Spot should be cheaper
  expect_true(cost2$total_estimated < cost1$total_estimated)

  # More workers = higher cost
  cost3 <- estimate_cost(20, 4, "8GB", 1, "EC2", "c6a.large", FALSE)
  expect_true(cost3$total_estimated > cost1$total_estimated)

  # Longer runtime = higher cost
  cost4 <- estimate_cost(10, 4, "8GB", 2, "EC2", "c6a.large", FALSE)
  expect_true(cost4$total_estimated > cost1$total_estimated)
})
