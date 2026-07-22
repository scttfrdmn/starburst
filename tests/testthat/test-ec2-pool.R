test_that("start_warm_pool lazily provisions a missing capacity provider", {
  skip_if_not_installed("mockery")

  backend <- list(
    region = "us-east-1", cluster = "starburst-cluster",
    cluster_name = "starburst-cluster", instance_type = "c8a.xlarge",
    architecture = "X86_64", use_spot = TRUE,
    capacity_provider_name = "starburst-c8a-xlarge",
    asg_name = "starburst-asg-c8a-xlarge", workers = 5
  )

  # ASG does NOT exist -> empty AutoScalingGroups.
  autoscaling <- list(
    describe_auto_scaling_groups = function(...) list(AutoScalingGroups = list()),
    set_desired_capacity = function(...) stop("stop-after-provision")  # sentinel
  )
  mockery::stub(start_warm_pool, "get_autoscaling_client", function(...) autoscaling)
  mockery::stub(start_warm_pool, "get_ecs_client", function(...) list())

  provisioned <- mockery::mock(invisible(TRUE))
  mockery::stub(start_warm_pool, "setup_ec2_capacity_provider", provisioned)

  # Missing ASG -> provision, then hit the set_desired_capacity sentinel.
  expect_error(start_warm_pool(backend, capacity = 5), "stop-after-provision")
  mockery::expect_called(provisioned, 1)
})

test_that("start_warm_pool does NOT re-provision an existing capacity provider", {
  skip_if_not_installed("mockery")

  backend <- list(
    region = "us-east-1", cluster = "starburst-cluster",
    cluster_name = "starburst-cluster", instance_type = "c7g.xlarge",
    architecture = "ARM64", use_spot = TRUE,
    capacity_provider_name = "starburst-c7g-xlarge",
    asg_name = "starburst-asg-c7g-xlarge", workers = 5
  )

  # ASG already exists.
  autoscaling <- list(
    describe_auto_scaling_groups = function(...)
      list(AutoScalingGroups = list(list(AutoScalingGroupName = backend$asg_name))),
    set_desired_capacity = function(...) stop("stop-after-scale")  # sentinel
  )
  mockery::stub(start_warm_pool, "get_autoscaling_client", function(...) autoscaling)
  mockery::stub(start_warm_pool, "get_ecs_client", function(...) list())

  provisioned <- mockery::mock(invisible(TRUE))
  mockery::stub(start_warm_pool, "setup_ec2_capacity_provider", provisioned)

  expect_error(start_warm_pool(backend, capacity = 5), "stop-after-scale")
  mockery::expect_called(provisioned, 0)  # existing ASG -> no provisioning
})
