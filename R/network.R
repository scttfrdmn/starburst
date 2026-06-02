#' VPC, subnet, and security group management for staRburst
#'
#' @name network
#' @keywords internal
NULL

#' Get starburst subnets
#'
#' @param region AWS region
#' @return Vector of subnet IDs
#' @keywords internal
get_starburst_subnets <- function(region) {
  config <- get_starburst_config()
  config$subnets
}

#' Get starburst security groups
#'
#' @param region AWS region
#' @return Vector of security group IDs
#' @keywords internal
get_starburst_security_groups <- function(region) {
  config <- get_starburst_config()
  config$security_groups
}

#' Get or create subnets
#'
#' @keywords internal
get_or_create_subnets <- function(vpc_id, region) {
  ec2 <- get_ec2_client(region)

  # Check for existing subnets with starburst tag
  subnets <- ec2$describe_subnets(
    Filters = list(
      list(Name = "vpc-id", Values = list(vpc_id)),
      list(Name = "tag:ManagedBy", Values = list("starburst"))
    )
  )

  if (length(subnets$Subnets) > 0) {
    return(vapply(subnets$Subnets, function(s) s$SubnetId, FUN.VALUE = character(1)))
  }

  # Get existing subnets to check if VPC has any
  all_subnets <- ec2$describe_subnets(
    Filters = list(
      list(Name = "vpc-id", Values = list(vpc_id))
    )
  )

  if (length(all_subnets$Subnets) > 0) {
    # Use existing subnets (don't create new ones unnecessarily)
    return(vapply(all_subnets$Subnets, function(s) s$SubnetId, FUN.VALUE = character(1)))
  }

  # Create subnets in multiple availability zones
  cat_info("   * Creating subnets for VPC...\n")

  # Get available AZs
  azs <- ec2$describe_availability_zones(
    Filters = list(
      list(Name = "region-name", Values = list(region)),
      list(Name = "state", Values = list("available"))
    )
  )

  if (length(azs$AvailabilityZones) == 0) {
    stop("No availability zones found in region")
  }

  # Create subnets in first 2-3 AZs
  num_subnets <- min(3, length(azs$AvailabilityZones))
  subnet_ids <- character(0)

  for (i in 1:num_subnets) {
    az <- azs$AvailabilityZones[[i]]$ZoneName
    cidr_block <- sprintf("10.0.%d.0/24", i)

    tryCatch({
      subnet <- ec2$create_subnet(
        VpcId = vpc_id,
        CidrBlock = cidr_block,
        AvailabilityZone = az
      )

      subnet_id <- subnet$Subnet$SubnetId

      # Tag subnet
      ec2$create_tags(
        Resources = list(subnet_id),
        Tags = list(
          list(Key = "Name", Value = sprintf("starburst-subnet-%d", i)),
          list(Key = "ManagedBy", Value = "starburst")
        )
      )

      # Enable auto-assign public IP
      ec2$modify_subnet_attribute(
        SubnetId = subnet_id,
        MapPublicIpOnLaunch = list(Value = TRUE)
      )

      subnet_ids <- c(subnet_ids, subnet_id)
      cat_info(sprintf("   * Created subnet: %s in %s\n", subnet_id, az))

    }, error = function(e) {
      cat_warn(sprintf("   * Failed to create subnet in %s: %s\n", az, e$message))
    })
  }

  if (length(subnet_ids) == 0) {
    stop("Failed to create any subnets")
  }

  return(subnet_ids)
}

#' Get or create security group
#'
#' @keywords internal
get_or_create_security_group <- function(vpc_id, region) {
  ec2 <- get_ec2_client(region)

  # Look for existing starburst security group
  sgs <- ec2$describe_security_groups(
    Filters = list(
      list(Name = "vpc-id", Values = list(vpc_id)),
      list(Name = "group-name", Values = list("starburst-worker"))
    )
  )

  if (length(sgs$SecurityGroups) > 0) {
    return(sgs$SecurityGroups[[1]]$GroupId)
  }

  # Create security group
  sg <- ec2$create_security_group(
    GroupName = "starburst-worker",
    Description = "Security group for staRburst workers",
    VpcId = vpc_id
  )

  sg$GroupId
}

#' Get VPC configuration for ECS tasks
#'
#' @keywords internal
get_vpc_config <- function(region) {
  ec2 <- get_ec2_client(region)

  # Get default VPC
  vpcs <- ec2$describe_vpcs(
    Filters = list(
      list(Name = "isDefault", Values = list("true"))
    )
  )

  if (length(vpcs$Vpcs) == 0) {
    stop("No default VPC found. Please create a VPC in region: ", region)
  }

  vpc_id <- vpcs$Vpcs[[1]]$VpcId

  # Get or create subnets
  subnets <- get_or_create_subnets(vpc_id, region)

  if (length(subnets) == 0) {
    stop("Failed to create subnets in VPC: ", vpc_id)
  }

  # Get or create security group
  sg_id <- get_or_create_security_group(vpc_id, region)

  list(
    vpc_id = vpc_id,
    subnets = as.list(subnets),
    security_groups = list(sg_id)
  )
}
