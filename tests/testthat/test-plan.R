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

test_that("starburst_map and starburst_cluster expose backend override args", {
  # Guards against the regression where the changelog promised launch_type/
  # instance_type/use_spot on these functions but the signatures lacked them
  # (so the args silently fell into ... and were passed to .f).
  for (fn in list(starburst_map, starburst_cluster)) {
    args <- names(formals(fn))
    expect_true(all(c("launch_type", "instance_type", "use_spot") %in% args))
    expect_identical(eval(formals(fn)$launch_type), "EC2")
    expect_identical(eval(formals(fn)$use_spot), TRUE)
  }
})

test_that("starburst_map forwards backend overrides to plan.starburst", {
  skip_if_not_installed("mockery")

  captured <- NULL
  # Stop execution right after plan.starburst is called by throwing a sentinel,
  # so the test never touches AWS/future.
  mockery::stub(starburst_map, "plan.starburst", function(...) {
    captured <<- list(...)
    stop("stop-after-plan")
  })
  mockery::stub(starburst_map, "get_starburst_config", function() list(region = "us-east-1"))

  expect_error(
    starburst_map(1:3, function(x) x,
                  launch_type = "FARGATE", instance_type = "c6a.large",
                  use_spot = FALSE, .progress = FALSE),
    "stop-after-plan"
  )
  expect_equal(captured$launch_type, "FARGATE")
  expect_equal(captured$instance_type, "c6a.large")
  expect_false(captured$use_spot)
})
