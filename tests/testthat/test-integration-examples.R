# Integration Tests Using Examples
#
# These tests run the example scripts to validate end-to-end functionality.
# Set RUN_INTEGRATION_TESTS=TRUE to enable (skipped by default).
# Set USE_STARBURST=TRUE to test with AWS (otherwise tests local execution).

skip_if_no_integration <- function() {
  skip_if_not(
    Sys.getenv("RUN_INTEGRATION_TESTS") == "TRUE",
    "Integration tests disabled. Set RUN_INTEGRATION_TESTS=TRUE to enable."
  )
}

test_that("Monte Carlo example runs locally", {
  skip_if_no_integration()

  # Run example without staRburst
  result <- system2(
    "Rscript",
    args = c("examples/01-monte-carlo-portfolio.R"),
    env = c("USE_STARBURST=FALSE"),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)  # NULL status = success (0)
  expect_true(file.exists("monte-carlo-results-local.rds"))

  # Verify results structure
  results <- readRDS("monte-carlo-results-local.rds")
  expect_type(results$results, "list")
  expect_true(results$elapsed > 0)
  expect_equal(results$mode, "local")

  # Cleanup
  unlink("monte-carlo-results-local.rds")
})

test_that("Monte Carlo example runs with staRburst", {
  skip_if_no_integration()
  skip_if_not(
    Sys.getenv("USE_STARBURST") == "TRUE",
    "AWS tests disabled. Set USE_STARBURST=TRUE to enable."
  )

  # Run example with staRburst
  result <- system2(
    "Rscript",
    args = c("examples/01-monte-carlo-portfolio.R"),
    env = c(
      "USE_STARBURST=TRUE",
      "STARBURST_WORKERS=10",  # Small worker count for testing
      paste0("AWS_PROFILE=", Sys.getenv("AWS_PROFILE", "aws"))
    ),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("monte-carlo-results-aws.rds"))

  # Verify results structure
  results <- readRDS("monte-carlo-results-aws.rds")
  expect_type(results$results, "list")
  expect_true(results$elapsed > 0)
  expect_equal(results$mode, "aws")
  expect_equal(results$workers, 10)

  # Cleanup
  unlink("monte-carlo-results-aws.rds")
})

test_that("Bootstrap example runs locally", {
  skip_if_no_integration()

  result <- system2(
    "Rscript",
    args = c("examples/02-bootstrap-confidence-intervals.R"),
    env = c("USE_STARBURST=FALSE"),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("bootstrap-results-local.rds"))

  results <- readRDS("bootstrap-results-local.rds")
  expect_type(results$boot_results, "list")
  expect_length(results$ci, 2)
  expect_true(results$ci[1] < results$ci[2])

  unlink("bootstrap-results-local.rds")
})

test_that("Bootstrap example runs with staRburst", {
  skip_if_no_integration()
  skip_if_not(Sys.getenv("USE_STARBURST") == "TRUE")

  result <- system2(
    "Rscript",
    args = c("examples/02-bootstrap-confidence-intervals.R"),
    env = c(
      "USE_STARBURST=TRUE",
      "STARBURST_WORKERS=10",
      paste0("AWS_PROFILE=", Sys.getenv("AWS_PROFILE", "aws"))
    ),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("bootstrap-results-aws.rds"))

  unlink("bootstrap-results-aws.rds")
})

test_that("Data processing example runs locally", {
  skip_if_no_integration()

  result <- system2(
    "Rscript",
    args = c("examples/03-parallel-data-processing.R"),
    env = c("USE_STARBURST=FALSE"),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("processing-results-local.rds"))

  results <- readRDS("processing-results-local.rds")
  expect_type(results$chunk_stats, "list")
  expect_true(length(results$chunk_stats) > 0)

  unlink("processing-results-local.rds")
})

test_that("Data processing example runs with staRburst", {
  skip_if_no_integration()
  skip_if_not(Sys.getenv("USE_STARBURST") == "TRUE")

  result <- system2(
    "Rscript",
    args = c("examples/03-parallel-data-processing.R"),
    env = c(
      "USE_STARBURST=TRUE",
      "STARBURST_WORKERS=10",
      paste0("AWS_PROFILE=", Sys.getenv("AWS_PROFILE", "aws"))
    ),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("processing-results-aws.rds"))

  unlink("processing-results-aws.rds")
})

test_that("Grid search example runs locally", {
  skip_if_no_integration()

  result <- system2(
    "Rscript",
    args = c("examples/04-grid-search-tuning.R"),
    env = c("USE_STARBURST=FALSE"),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("grid-search-results-local.rds"))

  results <- readRDS("grid-search-results-local.rds")
  expect_type(results$results, "list")
  expect_type(results$best_params, "list")
  expect_true(results$best_params$cv_score > 0)

  unlink("grid-search-results-local.rds")
})

test_that("Grid search example runs with staRburst", {
  skip_if_no_integration()
  skip_if_not(Sys.getenv("USE_STARBURST") == "TRUE")

  result <- system2(
    "Rscript",
    args = c("examples/04-grid-search-tuning.R"),
    env = c(
      "USE_STARBURST=TRUE",
      "STARBURST_WORKERS=10",
      paste0("AWS_PROFILE=", Sys.getenv("AWS_PROFILE", "aws"))
    ),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_equal(attr(result, "status"), NULL)
  expect_true(file.exists("grid-search-results-aws.rds"))

  unlink("grid-search-results-aws.rds")
})

test_that("All examples produce consistent results", {
  skip_if_no_integration()
  skip_if_not(Sys.getenv("USE_STARBURST") == "TRUE")

  # This test verifies that AWS and local execution produce similar results
  # (within statistical tolerance for random processes)

  # Run Monte Carlo both ways with same seed
  system2(
    "Rscript",
    args = c("examples/01-monte-carlo-portfolio.R"),
    env = c("USE_STARBURST=FALSE"),
    stdout = FALSE,
    stderr = FALSE
  )

  system2(
    "Rscript",
    args = c("examples/01-monte-carlo-portfolio.R"),
    env = c(
      "USE_STARBURST=TRUE",
      "STARBURST_WORKERS=10",
      paste0("AWS_PROFILE=", Sys.getenv("AWS_PROFILE", "aws"))
    ),
    stdout = FALSE,
    stderr = FALSE
  )

  # Compare results (should be statistically similar)
  local <- readRDS("monte-carlo-results-local.rds")
  aws <- readRDS("monte-carlo-results-aws.rds")

  local_means <- sapply(local$results, function(x) x$final_value)
  aws_means <- sapply(aws$results, function(x) x$final_value)

  # Results should be highly correlated (same random seeds)
  expect_true(cor(local_means, aws_means) > 0.99)

  # Cleanup
  unlink(c("monte-carlo-results-local.rds", "monte-carlo-results-aws.rds"))
})
