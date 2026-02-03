test_that("get_or_create_subnets returns existing tagged subnets", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock EC2 client
  ec2_client <- list(
    describe_subnets = function(Filters) {
      # Check if filtering by starburst tag
      if (any(sapply(Filters, function(f) {
        f$Name == "tag:ManagedBy" && "starburst" %in% f$Values
      }))) {
        # Return starburst-tagged subnets
        list(
          Subnets = list(
            list(SubnetId = "subnet-123"),
            list(SubnetId = "subnet-456")
          )
        )
      } else {
        list(Subnets = list())
      }
    }
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  result <- get_or_create_subnets("vpc-123", "us-east-1")

  expect_equal(result, c("subnet-123", "subnet-456"))
})

test_that("get_or_create_subnets uses existing untagged subnets", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock EC2 client
  ec2_client <- list(
    describe_subnets = function(Filters) {
      # Check if filtering by starburst tag
      has_tag_filter <- any(sapply(Filters, function(f) {
        f$Name == "tag:ManagedBy"
      }))

      if (has_tag_filter) {
        # No starburst-tagged subnets
        list(Subnets = list())
      } else {
        # Return existing subnets
        list(
          Subnets = list(
            list(SubnetId = "subnet-existing-1"),
            list(SubnetId = "subnet-existing-2")
          )
        )
      }
    }
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  result <- get_or_create_subnets("vpc-123", "us-east-1")

  expect_equal(result, c("subnet-existing-1", "subnet-existing-2"))
})

test_that("get_or_create_subnets creates subnets in multiple AZs", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  subnets_created <- list()

  # Mock EC2 client
  ec2_client <- list(
    describe_subnets = function(...) {
      list(Subnets = list())  # No existing subnets
    },
    describe_availability_zones = function(...) {
      list(
        AvailabilityZones = list(
          list(ZoneName = "us-east-1a"),
          list(ZoneName = "us-east-1b"),
          list(ZoneName = "us-east-1c"),
          list(ZoneName = "us-east-1d")
        )
      )
    },
    create_subnet = function(VpcId, CidrBlock, AvailabilityZone) {
      subnet_id <- paste0("subnet-", length(subnets_created) + 1)
      subnets_created[[subnet_id]] <<- list(
        VpcId = VpcId,
        CidrBlock = CidrBlock,
        AvailabilityZone = AvailabilityZone
      )
      list(Subnet = list(SubnetId = subnet_id))
    },
    create_tags = function(...) {
      list()
    },
    modify_subnet_attribute = function(...) {
      list()
    }
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  result <- get_or_create_subnets("vpc-123", "us-east-1")

  # Should create 3 subnets (min of 3 and number of AZs)
  expect_length(result, 3)
  expect_length(subnets_created, 3)

  # Check CIDR blocks
  expect_equal(subnets_created[[1]]$CidrBlock, "10.0.1.0/24")
  expect_equal(subnets_created[[2]]$CidrBlock, "10.0.2.0/24")
  expect_equal(subnets_created[[3]]$CidrBlock, "10.0.3.0/24")

  # Check AZs
  expect_equal(subnets_created[[1]]$AvailabilityZone, "us-east-1a")
  expect_equal(subnets_created[[2]]$AvailabilityZone, "us-east-1b")
  expect_equal(subnets_created[[3]]$AvailabilityZone, "us-east-1c")
})

test_that("get_or_create_subnets limits to 3 subnets", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  subnets_created <- 0

  # Mock EC2 client with many AZs
  ec2_client <- list(
    describe_subnets = function(...) {
      list(Subnets = list())
    },
    describe_availability_zones = function(...) {
      list(
        AvailabilityZones = list(
          list(ZoneName = "us-east-1a"),
          list(ZoneName = "us-east-1b"),
          list(ZoneName = "us-east-1c"),
          list(ZoneName = "us-east-1d"),
          list(ZoneName = "us-east-1e"),
          list(ZoneName = "us-east-1f")
        )
      )
    },
    create_subnet = function(...) {
      subnets_created <<- subnets_created + 1
      subnet_id <- paste0("subnet-", subnets_created)
      list(Subnet = list(SubnetId = subnet_id))
    },
    create_tags = function(...) list(),
    modify_subnet_attribute = function(...) list()
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  result <- get_or_create_subnets("vpc-123", "us-east-1")

  # Should only create 3 subnets
  expect_equal(subnets_created, 3)
  expect_length(result, 3)
})

test_that("get_or_create_subnets handles creation errors gracefully", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  attempt <- 0

  # Mock EC2 client
  ec2_client <- list(
    describe_subnets = function(...) {
      list(Subnets = list())
    },
    describe_availability_zones = function(...) {
      list(
        AvailabilityZones = list(
          list(ZoneName = "us-east-1a"),
          list(ZoneName = "us-east-1b"),
          list(ZoneName = "us-east-1c")
        )
      )
    },
    create_subnet = function(...) {
      attempt <<- attempt + 1
      if (attempt == 2) {
        stop("Subnet creation failed")
      }
      list(Subnet = list(SubnetId = paste0("subnet-", attempt)))
    },
    create_tags = function(...) list(),
    modify_subnet_attribute = function(...) list()
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  result <- get_or_create_subnets("vpc-123", "us-east-1")

  # Should return 2 subnets (1 failed)
  expect_length(result, 2)
})

test_that("get_or_create_subnets fails if no subnets created", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  # Mock EC2 client that always fails
  ec2_client <- list(
    describe_subnets = function(...) {
      list(Subnets = list())
    },
    describe_availability_zones = function(...) {
      list(
        AvailabilityZones = list(
          list(ZoneName = "us-east-1a")
        )
      )
    },
    create_subnet = function(...) {
      stop("Creation failed")
    }
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  expect_error(
    get_or_create_subnets("vpc-123", "us-east-1"),
    "Failed to create any subnets"
  )
})

test_that("get_or_create_subnets enables auto-assign public IP", {
  skip_on_cran()
  skip_if_not_installed("mockery")

  public_ip_enabled <- list()

  # Mock EC2 client
  ec2_client <- list(
    describe_subnets = function(...) {
      list(Subnets = list())
    },
    describe_availability_zones = function(...) {
      list(
        AvailabilityZones = list(
          list(ZoneName = "us-east-1a")
        )
      )
    },
    create_subnet = function(...) {
      list(Subnet = list(SubnetId = "subnet-1"))
    },
    create_tags = function(...) list(),
    modify_subnet_attribute = function(SubnetId, MapPublicIpOnLaunch) {
      public_ip_enabled[[SubnetId]] <<- MapPublicIpOnLaunch$Value
      list()
    }
  )

  mockery::stub(get_or_create_subnets, "get_ec2_client", function(...) {
    ec2_client
  })

  get_or_create_subnets("vpc-123", "us-east-1")

  expect_true(public_ip_enabled[["subnet-1"]])
})
