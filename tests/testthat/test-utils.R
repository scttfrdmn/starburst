test_that("null coalesce operator works", {
  `%||%` <- starburst:::`%||%`

  expect_equal(NULL %||% "default", "default")
  expect_equal("value" %||% "default", "value")
  expect_equal(0 %||% "default", 0)
  expect_equal(FALSE %||% "default", FALSE)
})

test_that("validate_workers checks bounds", {
  expect_error(validate_workers(-1))
  expect_error(validate_workers(0))
  expect_error(validate_workers(10001))
  expect_silent(validate_workers(1))
  expect_silent(validate_workers(100))
  expect_silent(validate_workers(10000))
})

test_that("validate_cpu checks valid values", {
  expect_silent(validate_cpu(1))
  expect_silent(validate_cpu(2))
  expect_silent(validate_cpu(4))
  expect_silent(validate_cpu(8))
  expect_silent(validate_cpu(16))

  expect_error(validate_cpu(3))
  expect_error(validate_cpu(32))
})

test_that("estimate_cost calculates correctly", {
  # 1 worker, 4 vCPU, 8GB, 1 hour
  cost <- estimate_cost(1, 4, "8GB", 1)

  expect_type(cost, "list")
  expect_true("per_worker" %in% names(cost))
  expect_true("per_hour" %in% names(cost))
  expect_true("total_estimated" %in% names(cost))

  # Cost should be positive
  expect_gt(cost$per_worker, 0)
  expect_gt(cost$per_hour, 0)

  # Multiple workers should scale linearly
  cost_100 <- estimate_cost(100, 4, "8GB", 1)
  expect_equal(cost_100$per_hour, cost$per_worker * 100)
})
