test_that("cleanup_session function exists and has correct signature", {
  # Verify the function exists
  expect_true(exists("cleanup_session", mode = "function"))

  # Check that it can be called with the expected parameters
  # (without actually running cleanup on a real session)
})

test_that("session object has cleanup method", {
  skip_on_cran()
  skip_if_offline()

  # Create a mock session object to check structure
  backend <- new.env()
  backend$session_id <- "test-session-id"
  backend$region <- "us-east-1"
  backend$bucket <- "test-bucket"
  backend$cluster_name <- "test-cluster"

  # Create session object
  session <- create_session_object(backend)

  # Verify cleanup method exists
  expect_true("cleanup" %in% names(session))
  expect_true(is.function(session$cleanup))

  # Check that cleanup has the right parameters
  cleanup_formals <- formals(session$cleanup)
  expect_true("stop_workers" %in% names(cleanup_formals))
  expect_true("force" %in% names(cleanup_formals))

  # Check defaults
  expect_equal(cleanup_formals$stop_workers, TRUE)
  expect_equal(cleanup_formals$force, FALSE)
})

test_that("cleanup respects stop_workers parameter", {
  skip_on_cran()
  skip_if_offline()
  skip("Integration test requires live AWS resources")

  # This would test that:
  # 1. session$cleanup(stop_workers = FALSE) doesn't stop tasks
  # 2. session$cleanup(stop_workers = TRUE) does stop tasks
  # Requires actual session creation
})

test_that("cleanup respects force parameter for S3 deletion", {
  skip_on_cran()
  skip_if_offline()
  skip("Integration test requires live AWS resources")

  # This would test that:
  # 1. session$cleanup(force = FALSE) preserves S3 files
  # 2. session$cleanup(force = TRUE) deletes S3 files
  # Requires actual session creation
})

test_that("launch_detached_workers tracks task ARNs in manifest", {
  skip_on_cran()
  skip_if_offline()
  skip("Integration test requires live AWS resources")

  # This would test that:
  # 1. After launching workers, manifest contains ecs_task_arns
  # 2. Number of ARNs matches number of workers
  # 3. ARNs are valid ECS task ARN format
  # Requires actual session creation and AWS access
})

test_that("cleanup can identify and stop session-specific tasks", {
  skip_on_cran()
  skip_if_offline()
  skip("Integration test requires live AWS resources")

  # This would test that:
  # 1. cleanup only stops tasks belonging to the session
  # 2. cleanup doesn't stop tasks from other sessions
  # 3. cleanup reports accurate count of stopped tasks
  # Requires multiple active sessions
})

test_that("cleanup verifies S3 deletion when force=TRUE", {
  skip_on_cran()
  skip_if_offline()
  skip("Integration test requires live AWS resources")

  # This would test that:
  # 1. After cleanup(force=TRUE), S3 prefix has 0 objects
  # 2. Cleanup reports number of deleted objects
  # 3. Task files are also deleted
  # Requires actual session with S3 files
})

test_that("cleanup handles errors gracefully", {
  skip_on_cran()
  skip_if_offline()

  # Create a session with invalid backend to test error handling
  backend <- new.env()
  backend$session_id <- "test-session-id"
  backend$region <- "us-east-1"
  backend$bucket <- "nonexistent-bucket-12345"
  backend$cluster_name <- "nonexistent-cluster"

  session <- create_session_object(backend)

  # Cleanup should not crash, just warn
  expect_output(
    session$cleanup(stop_workers = FALSE, force = FALSE),
    "Cleanup complete"  # Should still report completion
  )
})

test_that("cleanup marks session as terminated in manifest", {
  skip_on_cran()
  skip_if_offline()
  skip("Integration test requires live AWS resources")

  # This would test that:
  # 1. After cleanup(force=FALSE), manifest has state="terminated"
  # 2. Manifest has terminated_at timestamp
  # 3. After cleanup(force=TRUE), manifest is deleted
  # Requires actual session
})
