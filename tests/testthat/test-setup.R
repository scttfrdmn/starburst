test_that("starburst_setup provisions default EC2 capacity by default", {
  skip_if_not_installed("mockery")

  # Stub every AWS collaborator so no network/credentials are touched.
  mockery::stub(starburst_setup, "check_aws_credentials", function() TRUE)
  mockery::stub(starburst_setup, "create_starburst_bucket", function(...) "starburst-test-bucket")
  mockery::stub(starburst_setup, "create_ecr_repository",
                function(...) list(repositoryUri = "acct.dkr.ecr/starburst-worker"))
  mockery::stub(starburst_setup, "create_ecs_cluster",
                function(...) list(clusterName = "starburst-cluster"))
  mockery::stub(starburst_setup, "setup_vpc_resources",
                function(...) list(vpc_id = "vpc-1", subnets = c("s-1"),
                                   security_groups = c("sg-1")))
  mockery::stub(starburst_setup, "get_aws_account_id", function() "123456789012")
  mockery::stub(starburst_setup, "save_config", function(...) invisible(TRUE))
  mockery::stub(starburst_setup, "check_fargate_quota",
                function(...) list(limit = 1000, increase_pending = FALSE))
  mockery::stub(starburst_setup, "build_initial_environment", function(...) "hash")

  ec2_mock <- mockery::mock(invisible(TRUE))
  mockery::stub(starburst_setup, "starburst_setup_ec2", ec2_mock)

  # setup_ec2 = TRUE (default): starburst_setup_ec2 must be called once, for the
  # default instance type, so the default EC2 backend works out of the box.
  starburst_setup(region = "us-east-1", force = TRUE, build_image = FALSE)
  mockery::expect_called(ec2_mock, 1)
  args <- mockery::mock_args(ec2_mock)[[1]]
  expect_true("c7g.xlarge" %in% unlist(args))
})

test_that("starburst_setup(setup_ec2 = FALSE) skips EC2 provisioning", {
  skip_if_not_installed("mockery")

  mockery::stub(starburst_setup, "check_aws_credentials", function() TRUE)
  mockery::stub(starburst_setup, "create_starburst_bucket", function(...) "b")
  mockery::stub(starburst_setup, "create_ecr_repository",
                function(...) list(repositoryUri = "uri"))
  mockery::stub(starburst_setup, "create_ecs_cluster",
                function(...) list(clusterName = "starburst-cluster"))
  mockery::stub(starburst_setup, "setup_vpc_resources",
                function(...) list(vpc_id = "vpc-1", subnets = c("s-1"),
                                   security_groups = c("sg-1")))
  mockery::stub(starburst_setup, "get_aws_account_id", function() "123456789012")
  mockery::stub(starburst_setup, "save_config", function(...) invisible(TRUE))
  mockery::stub(starburst_setup, "check_fargate_quota",
                function(...) list(limit = 1000, increase_pending = FALSE))

  ec2_mock <- mockery::mock(invisible(TRUE))
  mockery::stub(starburst_setup, "starburst_setup_ec2", ec2_mock)

  starburst_setup(region = "us-east-1", force = TRUE, build_image = FALSE,
                  setup_ec2 = FALSE)
  mockery::expect_called(ec2_mock, 0)
})
