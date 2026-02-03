test_that("plan.starburst validates inputs", {
  skip_if_not(is_setup_complete(), "staRburst not configured")

  expect_error(plan.starburst(workers = -1))
  expect_error(plan.starburst(workers = 0))
  expect_error(plan.starburst(cpu = 3))
  expect_error(plan.starburst(memory = "invalid"))
})

test_that("plan.starburst creates valid plan object", {
  skip_if_not(is_setup_complete(), "staRburst not configured")
  skip("Requires AWS credentials and setup")

  plan <- plan.starburst(workers = 10, cpu = 4, memory = "8GB")

  expect_s3_class(plan, "starburst")
  expect_s3_class(plan, "cluster")
  expect_s3_class(plan, "future")

  expect_true("cluster_id" %in% names(plan))
  expect_true("workers" %in% names(plan))
  expect_equal(plan$workers, 10)
  expect_equal(plan$cpu, 4)
})
