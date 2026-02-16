# Detached Sessions - Issues and Weaknesses Report

Generated: 2026-02-11

## Critical Issues

### 1. **No Error Handling in Worker Task Execution** ⚠️ CRITICAL

**Location:** `inst/templates/worker.R:228-258`

**Issue:** When executing tasks in detached mode (Future format),
there’s NO try-catch around the
[`eval()`](https://rdrr.io/r/base/eval.html) call. If a task throws an
error, the worker will crash instead of marking the task as failed.

``` r
# Current code (lines 228-258):
} else if (!is.null(task$expr)) {
    # NEW FORMAT: Future-based execution
    message("Task loaded (Future format)")
    message("Executing task...")

    # ... setup code ...

    # Evaluate expression - NO ERROR HANDLING!
    result_value <- eval(task$expr, envir = exec_env)

    result <- list(
      error = FALSE,
      value = result_value,
      stdout = "",
      conditions = list()
    )
}
```

**Impact:** - Workers crash on any task error - Task stays in “running”
state forever - No error information captured - Session becomes
unrecoverable

**Fix Required:**

``` r
result <- tryCatch({
  result_value <- eval(task$expr, envir = exec_env)
  list(
    error = FALSE,
    value = result_value,
    stdout = "",
    conditions = list()
  )
}, error = function(e) {
  list(
    error = TRUE,
    message = e$message,
    value = NULL,
    stdout = "",
    conditions = list()
  )
})
```

**Priority:** **CRITICAL** - Must fix before production use

------------------------------------------------------------------------

### 2. **No CloudWatch Logging for Detached Sessions** ⚠️ HIGH

**Location:** Task definition creation in `R/utils.R`

**Issue:** CloudWatch logging is configured for ephemeral mode but not
verified for detached sessions. Without logs, debugging worker failures
is nearly impossible.

**Current State:** - Logging configuration exists in
`R/utils.R:1295-1300` - Not tested with detached sessions - No log group
verification during session creation

**Impact:** - Cannot debug worker crashes - No visibility into task
execution - Difficult to diagnose S3 access issues - Poor operational
visibility

**Fix Required:** 1. Add log group creation in
[`initialize_detached_backend()`](https://scttfrdmn.github.io/starburst/reference/initialize_detached_backend.md)
2. Test CloudWatch logging with detached workers 3. Add log stream
querying to `session$status()` for recent errors 4. Document how to
access logs

**Priority:** **HIGH**

------------------------------------------------------------------------

### 3. **Race Condition in Manifest Updates** ⚠️ MEDIUM

**Location:** `R/session-state.R:78-118` -
[`update_session_manifest()`](https://scttfrdmn.github.io/starburst/reference/update_session_manifest.md)

**Issue:** The manifest update is NOT atomic. It downloads, modifies,
and uploads without using ETags for conditional writes. Multiple
concurrent updates can result in lost writes.

``` r
update_session_manifest <- function(session_id, updates, region, bucket) {
  # Download current manifest
  s3$download_file(...)
  manifest <- qs::qread(temp_file)

  # Apply updates
  for (name in names(updates)) {
    manifest[[name]] <- updates[[name]]  # RACE CONDITION HERE
  }

  # Upload (unconditionally!)
  s3$put_object(...)  # No ETag check!
}
```

**Scenario:** 1. User calls `session$submit()` → updates manifest
(total_tasks = 5) 2. Simultaneously, another `submit()` updates manifest
(total_tasks = 6) 3. One update overwrites the other 4. Task count
becomes incorrect

**Impact:** - Incorrect task statistics - Potential data loss in
manifest - Hard to detect/debug

**Fix Required:** Implement ETag-based atomic updates similar to task
claiming:

``` r
# Get current manifest WITH ETag
response <- s3$get_object(Bucket = bucket, Key = manifest_key)
etag <- response$ETag
manifest <- qs::qread(response$Body)

# Apply updates
# ...

# Conditional PUT
s3$put_object(
  Bucket = bucket,
  Key = manifest_key,
  Body = temp_file,
  IfMatch = etag  # Atomic!
)
```

**Priority:** **MEDIUM** (low probability but high impact)

------------------------------------------------------------------------

## High Priority Issues

### 4. **Incomplete Cleanup Implementation** ⚠️ HIGH

**Location:** `R/session-api.R:497-513` -
[`cleanup_session()`](https://scttfrdmn.github.io/starburst/reference/cleanup_session.md)

**Issue:** The cleanup function does almost nothing: - Doesn’t stop
running workers - Doesn’t delete S3 files - Doesn’t provide forced
termination option - Just prints a message

``` r
cleanup_session <- function(session) {
  # Stop any running tasks (optional - they will time out naturally)
  # For now, just mark session as cleaned up

  # Could delete S3 files if desired
  # For safety, we'll leave them for manual cleanup

  cat_success("✓ Session marked for cleanup\n")
  cat_info("   Workers will self-terminate after idle timeout\n")
  # ... that's it!
}
```

**Impact:** - Workers continue running for up to 5 minutes idle
timeout - S3 files accumulate indefinitely - No way to force-stop
misbehaving sessions - Costs continue even after “cleanup”

**Fix Required:** 1. **Add ECS task termination:** - Track worker task
ARNs in manifest - Call `ecs$stop_task()` for each worker 2. **Add
optional S3 cleanup:** - Parameter `delete_files = FALSE` for safety -
If TRUE, delete session S3 directory 3. **Add manifest cleanup
marker:** - Mark session as “terminated” in manifest - Workers check
this flag and exit immediately

**Priority:** **HIGH**

------------------------------------------------------------------------

### 5. **No Failed Task Handling in Results Collection** ⚠️ MEDIUM

**Location:** `R/session-api.R:393-471` -
[`collect_session_results()`](https://scttfrdmn.github.io/starburst/reference/collect_session_results.md)

**Issue:** The collection function only looks for
`state == "completed"`. Failed tasks are completely ignored.

``` r
# Skip if not completed or already collected
if (status$state != "completed" || task_id %in% names(results)) {
  next  # Failed tasks are skipped!
}
```

**Impact:** - Failed tasks silently disappear - User doesn’t know which
tasks failed - No error information available - Silent data loss

**Fix Required:**

``` r
# Collect both completed and failed results
if (status$state == "completed") {
  # Download result normally
} else if (status$state == "failed") {
  # Create error result object
  results[[task_id]] <- list(
    error = TRUE,
    message = status$error_message,
    failed_at = status$failed_at
  )
}
```

**Priority:** **MEDIUM**

------------------------------------------------------------------------

### 6. **Missing Documentation in README** ⚠️ MEDIUM

**Location:** `README.md`

**Issue:** The main README doesn’t mention detached sessions AT ALL.
Users won’t discover this major feature.

**Current README sections:** - ✅ Basic
[`starburst_map()`](https://scttfrdmn.github.io/starburst/reference/starburst_map.md)
usage - ✅ Quick start examples - ✅ Cluster reuse - ❌ **No mention of
detached sessions** - ❌ **No mention of
[`starburst_session()`](https://scttfrdmn.github.io/starburst/reference/starburst_session.md)** -
❌ **No link to detached sessions vignette**

**Impact:** - Poor feature discoverability - Users unaware of
long-running computation support - Competitive disadvantage (this is a
killer feature!)

**Fix Required:** Add section to README:

``` markdown
## Long-Running Computations

For analyses that take hours or days, use detached sessions:

```r
# Start computation and close laptop
session <- starburst_session(workers = 50)
lapply(1:10000, function(i) session$submit(quote(long_analysis(i))))
session_id <- session$session_id

# Come back later and check progress
session <- starburst_session_attach(session_id)
results <- session$collect()
```

See [Detached Sessions
Guide](https://scttfrdmn.github.io/starburst/vignettes/detached-sessions.Rmd)
for details.

    **Priority:** **MEDIUM**

    ---

    ## Medium Priority Issues

    ### 7. **Debug Logging Left in Production Code** ⚠️ LOW

    **Location:** `R/plan-starburst.R:42,241,255,261-262,270-271`

    **Issue:** Multiple `cat("DEBUG: ...")` statements in production code.

    ```r
    cat("DEBUG: plan.starburst() CALLED\n")
    cat_info("DEBUG: About to call future::tweak()\n")
    cat_info("DEBUG: tweak() returned successfully\n")
    cat_info(sprintf("DEBUG: Setting backend in options (is.null: %s)\n", ...))
    cat_info(sprintf("DEBUG: Backend attribute set (is.null: %s)\n", ...))

**Impact:** - Confusing output for users - Looks unprofessional - May
expose implementation details

**Fix Required:** Remove all DEBUG statements or wrap in
`if (getOption("starburst.debug", FALSE))`

**Priority:** **LOW** (cosmetic but should fix)

------------------------------------------------------------------------

### 8. **No Progress Indicator During Collection** ⚠️ LOW

**Location:** `R/session-api.R:393-471` -
[`collect_session_results()`](https://scttfrdmn.github.io/starburst/reference/collect_session_results.md)

**Issue:** When waiting for results with `wait = TRUE`, there’s no
progress indicator. User just sees nothing for potentially hours.

**Current behavior:**

``` r
repeat {
  # Poll for results
  Sys.sleep(2)  # Silent waiting
}
```

**Fix Required:**

``` r
if (wait) {
  cat_info("⏳ Waiting for results to complete...\n")
  last_status_time <- Sys.time()

  repeat {
    # Show progress every 30 seconds
    if (difftime(Sys.time(), last_status_time, units = "secs") > 30) {
      status <- get_session_status(session)
      cat_info(sprintf("   Progress: %d/%d completed (%.1f%%)\n",
                      status$completed, status$total,
                      100 * status$completed / status$total))
      last_status_time <- Sys.time()
    }
    # ...
  }
}
```

**Priority:** **LOW** (UX improvement)

------------------------------------------------------------------------

### 9. **No Task Result Size Limits** ⚠️ MEDIUM

**Location:** `inst/templates/worker.R:268-283` - `upload_result()`

**Issue:** No check on result size before uploading to S3. Large results
could cause memory issues or S3 upload failures.

**Impact:** - Worker crashes on large results - S3 upload timeouts -
Hidden memory exhaustion - No user guidance on result size

**Fix Required:**

``` r
upload_result <- function(result, task_id, s3, bucket) {
  result_file <- tempfile(fileext = ".qs")
  qs::qsave(result, result_file)

  # Check size
  size_mb <- file.size(result_file) / 1024^2
  if (size_mb > 500) {  # 500 MB limit
    warning(sprintf("Result size %.1f MB exceeds recommended limit of 500 MB", size_mb))
    # Consider chunking or streaming for large results
  }

  # Upload with progress
  s3$put_object(...)
}
```

**Priority:** **MEDIUM**

------------------------------------------------------------------------

### 10. **Insufficient Validation in Session Creation** ⚠️ LOW

**Location:** `R/session-api.R:55-88` -
[`starburst_session()`](https://scttfrdmn.github.io/starburst/reference/starburst_session.md)

**Issue:** Limited input validation: - No max workers limit (could
accidentally create 1000s) - No timeout range checks - No memory
validation against instance type - No bucket existence check

**Examples of missing validation:**

``` r
# User could accidentally do:
session <- starburst_session(workers = 10000)  # No check!
session <- starburst_session(timeout = -100)   # Negative timeout!
session <- starburst_session(memory = "999GB") # Impossible memory!
```

**Fix Required:**

``` r
starburst_session <- function(workers = 10, ...) {
  # Validate workers
  if (workers > 500) {
    stop("Maximum 500 workers allowed. For larger scale, contact support.")
  }

  # Validate timeout
  if (timeout < 60 || timeout > 86400) {
    stop("Timeout must be between 60 seconds and 24 hours")
  }

  # Validate memory against instance type
  # ...

  # Check bucket exists and is accessible
  # ...
}
```

**Priority:** **LOW** (prevents user errors)

------------------------------------------------------------------------

## Documentation & Tutorial Gaps

### 11. **Missing Troubleshooting Guide** 📚 HIGH

**Issue:** No troubleshooting documentation for common issues: - What if
workers don’t start? - What if tasks get stuck in “running”? - How to
debug task failures? - How to check CloudWatch logs? - How to manually
clean up sessions?

**Fix Required:** Create
`vignettes/troubleshooting-detached-sessions.Rmd`

------------------------------------------------------------------------

### 12. **No Migration Guide from Ephemeral to Detached** 📚 MEDIUM

**Issue:** Users with existing
[`starburst_map()`](https://scttfrdmn.github.io/starburst/reference/starburst_map.md)
code don’t know how to convert to detached sessions.

**Fix Required:** Add section to vignette:

``` markdown
## Migrating from starburst_map()

### Before (Ephemeral):
```r
results <- starburst_map(1:1000, expensive_fn, workers = 50)
```

### After (Detached):

``` r
session <- starburst_session(workers = 50)
lapply(1:1000, function(i) session$submit(quote(expensive_fn(i))))
results <- session$collect(wait = TRUE)
```

    ---

    ### 13. **Incomplete Error Handling Examples** 📚 MEDIUM

    **Location:** `vignettes/detached-sessions.Rmd:145-170`

    **Issue:** Error handling example shows checking `failed_task$error` but:
    - Doesn't explain how to get error messages
    - Doesn't show how to retry failed tasks
    - Doesn't explain failed task recovery

    **Fix Required:** Expand example with:
    ```r
    # Find and retry failed tasks
    status <- session$status()
    if (status$failed > 0) {
      # Get all statuses
      all_statuses <- list_task_statuses(...)
      failed_ids <- names(all_statuses)[sapply(all_statuses,
        function(s) s$state == "failed")]

      # Retry failed tasks
      for (task_id in failed_ids) {
        # Re-submit with original expression
        session$submit(...)
      }
    }

------------------------------------------------------------------------

### 14. **No Cost Estimation for Detached Sessions** 📚 LOW

**Issue:** Vignette doesn’t explain cost model for detached sessions: -
Workers running 24/7 until idle timeout - Cost of idle workers polling
for tasks - How to minimize costs

**Fix Required:** Add section:

``` markdown
## Cost Management

Detached sessions have different cost characteristics:

- **Workers poll continuously**: Even when idle, workers consume resources
- **Idle timeout**: Workers auto-terminate after 5 minutes idle
- **Cost optimization**: Start with fewer workers, submit in batches
- **Estimated costs**: $0.05-0.10 per worker-hour (Fargate)

### Best Practice:
```r
# Instead of:
session <- starburst_session(workers = 100)  # All running 24/7!

# Do this:
session <- starburst_session(workers = 10)   # Smaller pool
# Submit work in batches as needed
```

    ---

    ### 15. **No API Reference Documentation** 📚 MEDIUM

    **Issue:** No man pages for core functions:
    - `starburst_session()` - has roxygen but basic
    - `starburst_session_attach()` - no details
    - `starburst_list_sessions()` - no docs on return format
    - `session$submit()` - no parameter docs
    - `session$status()` - no return value docs
    - `session$collect()` - no wait/timeout behavior explained

    **Fix Required:** Enhance roxygen documentation with:
    - Full parameter descriptions
    - Return value details
    - Usage examples
    - Related functions
    - See also links

    ---

    ## Testing Gaps

    ### 16. **No Tests for Error Cases** ⚠️ HIGH

    **Issue:** Test coverage is good for happy path (36/36 passing) but missing:
    - Worker crash recovery
    - S3 access failures
    - Network interruptions
    - Timeout handling
    - Failed task scenarios
    - Race conditions with multiple sessions
    - Concurrent submit operations

    **Fix Required:** Add tests:
    ```r
    test_that("worker handles task execution errors gracefully", {
      session <- starburst_session(workers = 1)
      session$submit(quote(stop("Intentional error")))

      Sys.sleep(60)
      status <- session$status()

      expect_equal(status$failed, 1)
      expect_equal(status$completed, 0)
    })

    test_that("concurrent submits don't lose tasks", {
      # Stress test manifest updates
    })

**Priority:** **HIGH**

------------------------------------------------------------------------

### 17. **No Large-Scale Tests** ⚠️ MEDIUM

**Issue:** Largest test has 10 tasks and 2 workers. No tests for: - 100+
tasks - 50+ workers - Tasks running \> 1 hour - Large result sizes
(GB) - Session running \> 4 hours

**Impact:** Unknown behavior at scale

**Fix Required:** Add integration tests:

``` r
test_that("handles 1000 tasks across 50 workers", {
  # Scale test
})

test_that("session persists across 4 hour runtime", {
  # Longevity test
})
```

**Priority:** **MEDIUM**

------------------------------------------------------------------------

## Architecture & Design Issues

### 18. **No Monitoring/Metrics** ⚠️ LOW

**Issue:** No built-in metrics for: - Task throughput - Worker
utilization - Average task duration - Failure rate - S3 operation
latency

**Impact:** Difficult to optimize performance

**Fix Required:** Add metrics collection to manifest:

``` r
manifest$metrics <- list(
  total_task_duration_seconds = 0,
  total_s3_operations = 0,
  worker_idle_time_seconds = 0,
  task_failure_rate = 0.0
)
```

------------------------------------------------------------------------

### 19. **No Rate Limiting for S3 Operations** ⚠️ LOW

**Issue:** Workers poll S3 continuously without rate limiting. Could hit
S3 request rate limits with many workers.

**Impact:** - Potential S3 throttling errors - Unnecessary costs -
Degraded performance

**Fix Required:** Add exponential backoff in polling loop (partially
implemented but could be enhanced)

------------------------------------------------------------------------

### 20. **No Session Versioning** ⚠️ LOW

**Issue:** If manifest schema changes in future versions, old sessions
won’t be compatible. No version field in manifest.

**Fix Required:**

``` r
manifest <- list(
  version = "1.0",  # Add version
  session_id = session_id,
  # ...
)
```

------------------------------------------------------------------------

## Summary

### Critical (Fix Immediately):

1.  ⚠️ **Worker task execution has no error handling** - crashes on
    errors
2.  ⚠️ **No CloudWatch logging** - impossible to debug

### High Priority:

3.  Race condition in manifest updates
4.  Incomplete cleanup implementation
5.  No failed task handling
6.  Missing README documentation
7.  No troubleshooting guide
8.  No error case tests

### Medium Priority:

9.  No progress indicator during collection
10. No result size limits
11. No migration guide
12. Incomplete error examples
13. No API reference
14. No large-scale tests

### Low Priority:

15. Debug logging in production
16. Insufficient input validation
17. No cost estimation docs
18. No monitoring/metrics
19. No S3 rate limiting
20. No session versioning

## Recommendations

**Before Production:** 1. Fix critical issues \#1-2 (worker error
handling, logging) 2. Implement proper failed task handling 3. Complete
cleanup implementation 4. Add error case tests

**Before Public Release:** 5. Update README with detached sessions 6.
Create troubleshooting guide 7. Enhance API documentation 8. Add
migration guide

**Nice to Have:** 9. Monitoring/metrics 10. Large-scale tests 11. Rate
limiting 12. Progress indicators

------------------------------------------------------------------------

**Overall Assessment:**

The implementation is **functionally complete and well-architected**,
but has **critical gaps in error handling and observability** that must
be addressed before production use. The core atomic claiming and S3
state management are solid, but the worker execution path needs
hardening.

**Estimated effort to production-ready:** - Critical fixes: 1-2 days -
High priority: 3-4 days - Documentation: 2-3 days - **Total: ~1-2
weeks**

The foundation is excellent - these are polish and hardening issues, not
architectural problems.
