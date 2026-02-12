# Helper functions for AWS testing

#' Skip test if AWS credentials not available
skip_if_no_aws <- function() {
  has_creds <- tryCatch({
    # Try to get AWS credentials
    Sys.getenv("AWS_PROFILE") != "" ||
      (Sys.getenv("AWS_ACCESS_KEY_ID") != "" &&
       Sys.getenv("AWS_SECRET_ACCESS_KEY") != "")
  }, error = function(e) FALSE)

  if (!has_creds) {
    skip("AWS credentials not available")
  }
}

#' Skip test if not in CI/CD environment
skip_if_not_ci <- function() {
  is_ci <- Sys.getenv("CI") == "true" ||
           Sys.getenv("GITHUB_ACTIONS") == "true"

  if (!is_ci) {
    skip("Not in CI environment")
  }
}

#' Check if AWS integration tests should run
can_run_aws_tests <- function() {
  !identical(Sys.getenv("STARBURST_SKIP_AWS_TESTS"), "true") &&
    (Sys.getenv("AWS_PROFILE") != "" ||
     (Sys.getenv("AWS_ACCESS_KEY_ID") != "" &&
      Sys.getenv("AWS_SECRET_ACCESS_KEY") != ""))
}
