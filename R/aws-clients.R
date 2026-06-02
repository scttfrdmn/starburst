#' AWS service clients and credential helpers for staRburst
#'
#' @name aws-clients
#' @keywords internal
NULL

#' Check AWS credentials
#'
#' @return Logical indicating if credentials are valid
#' @keywords internal
check_aws_credentials <- function() {
  tryCatch({
    sts <- paws.security.identity::sts()
    identity <- sts$get_caller_identity()
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Get AWS account ID
#'
#' @return AWS account ID
#' @keywords internal
get_aws_account_id <- function() {
  sts <- paws.security.identity::sts()
  identity <- sts$get_caller_identity()
  identity$Account
}

#' Get S3 client
#'
#' @param region AWS region
#' @return S3 client
#' @keywords internal
get_s3_client <- function(region) {
  paws.storage::s3(config = list(region = region))
}

#' Get ECS client
#'
#' @param region AWS region
#' @return ECS client
#' @keywords internal
get_ecs_client <- function(region) {
  paws.compute::ecs(config = list(region = region))
}

#' Get ECR client
#'
#' @param region AWS region
#' @return ECR client
#' @keywords internal
get_ecr_client <- function(region) {
  paws.compute::ecr(config = list(region = region))
}

#' Get EC2 client
#'
#' @param region AWS region
#' @return EC2 client
#' @keywords internal
get_ec2_client <- function(region) {
  paws.compute::ec2(config = list(region = region))
}

#' Get Service Quotas client
#'
#' @param region AWS region
#' @return Service Quotas client
#' @keywords internal
get_service_quotas_client <- function(region) {
  paws.management::servicequotas(config = list(region = region))
}
