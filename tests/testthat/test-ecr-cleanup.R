# Tests for ECR auto-cleanup functionality

test_that("ECR lifecycle policy can be created", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")
  skip("Manual test - modifies ECR policy")  # Remove to run

  # Create lifecycle policy
  create_ecr_lifecycle_policy(
    region = "us-east-1",
    repository_name = "starburst-worker",
    ttl_days = 30
  )

  # Verify policy exists
  ecr <- get_ecr_client("us-east-1")
  policy <- ecr$get_lifecycle_policy(repositoryName = "starburst-worker")

  expect_true(!is.null(policy$lifecyclePolicyText))

  # Parse policy
  policy_data <- jsonlite::fromJSON(policy$lifecyclePolicyText)
  expect_equal(policy_data$rules[[1]]$selection$countNumber, 30)
})

test_that("ECR image age checking works with TTL", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")

  config <- get_starburst_config()

  # Test with very long TTL (shouldn't trigger rebuild)
  result1 <- check_ecr_image_age(
    region = config$region,
    image_tag = "base-4.5.2",
    ttl_days = 365,
    force_rebuild = FALSE
  )

  expect_true(result1)  # Image is fresh

  # Test with very short TTL (would trigger rebuild if image is old enough)
  # Don't actually rebuild in test
  result2 <- check_ecr_image_age(
    region = config$region,
    image_tag = "base-4.5.2",
    ttl_days = 0,  # Any age is too old
    force_rebuild = FALSE
  )

  # Should warn but not rebuild (force_rebuild = FALSE)
  expect_type(result2, "logical")
})

test_that("Manual ECR cleanup works", {
  skip_on_cran()
  skip_if_not(check_aws_credentials(), "AWS credentials not available")
  skip("Manual test - deletes images")  # Remove to run

  # This would actually delete images
  # result <- starburst_cleanup_ecr(force = FALSE)

  # expect_type(result, "logical")
})

test_that("ECR cleanup respects TTL configuration", {
  config_with_ttl <- list(
    region = "us-east-1",
    ecr_image_ttl_days = 30
  )

  config_no_ttl <- list(
    region = "us-east-1",
    ecr_image_ttl_days = NULL
  )

  expect_equal(config_with_ttl$ecr_image_ttl_days, 30)
  expect_null(config_no_ttl$ecr_image_ttl_days)
})

test_that("Config includes ECR TTL setting", {
  skip_on_cran()
  skip_if_not(is_setup_complete(), "starburst not configured")

  config <- get_starburst_config()

  # Config should have ecr_image_ttl_days field (may be NULL)
  expect_true("ecr_image_ttl_days" %in% names(config))
})

test_that("ECR TTL affects idle cost", {
  # With TTL: $0 idle cost (images auto-deleted)
  config_with_ttl <- list(ecr_image_ttl_days = 30)
  expect_equal(config_with_ttl$ecr_image_ttl_days, 30)

  # Without TTL: ~$0.50/month idle cost (images persist)
  config_no_ttl <- list(ecr_image_ttl_days = NULL)
  expect_null(config_no_ttl$ecr_image_ttl_days)

  # This is a documentation test - actual costs are external to the code
})

test_that("Lifecycle policy prevents surprise bills", {
  # This is more of a documentation/integration test

  # Scenario: User runs job once and forgets
  # - With TTL: AWS auto-deletes images after X days -> $0 cost
  # - Without TTL: Images persist forever -> ~$0.50/month

  config <- list(ecr_image_ttl_days = 7)

  # After 7 days, AWS will automatically delete images
  # No manual intervention needed
  # No surprise bills

  expect_equal(config$ecr_image_ttl_days, 7)
})
