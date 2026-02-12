# staRburst - Comprehensive Issues & Weaknesses Report

**Date:** 2026-02-11
**Scope:** Full project examination (all modes, infrastructure, security, documentation)

---

## 🚨 CRITICAL SECURITY ISSUES

### 1. **ECR Password Exposed in Shell Command** ⚠️ CRITICAL SECURITY

**Location:** `R/utils.R:894-899`

**Issue:** ECR password is passed directly to `echo` command, exposing it in:
- Process listings (`ps aux`)
- Shell history
- System logs
- Any process monitor

```r
password <- token_parts[2]

# SECURITY VULNERABILITY:
login_cmd <- sprintf("echo %s | docker login --username AWS --password-stdin %s",
                    shQuote(password), token_data$proxyEndpoint)
login_result <- system(login_cmd, ignore.stdout = TRUE, ignore.stderr = FALSE)
```

**Impact:**
- **CRITICAL**: Credentials exposed to any user on system
- Password visible in `ps aux` output
- Potential credential theft
- Violates AWS security best practices

**Fix Required:**
```r
# Use stdin without exposing password in command
temp_pw_file <- tempfile()
on.exit(unlink(temp_pw_file), add = TRUE)
writeLines(password, temp_pw_file)

login_cmd <- sprintf("docker login --username AWS --password-stdin %s < %s",
                    token_data$proxyEndpoint, shQuote(temp_pw_file))
login_result <- system(login_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
```

**Priority:** **CRITICAL - Fix immediately before any production use**

---

### 2. **No Error Handling in Worker Task Execution** ⚠️ CRITICAL

**Location:** `inst/templates/worker.R:228-258`

**Issue:** (Already documented in detached sessions report) - No try-catch around `eval(task$expr)` in Future-based execution.

**Priority:** **CRITICAL**

---

### 3. **Unsafe system() Calls** ⚠️ HIGH SECURITY

**Locations:**
- `R/utils.R:899` - Docker login
- `R/utils.R:914` - Docker buildx setup
- `R/utils.R:920` - Docker build
- `R/starburst-estimate.R` - Various Docker commands

**Issue:** Multiple `system()` calls without proper validation or escaping. While some use `shQuote()`, not all do consistently.

**Example:**
```r
# Line 914 - Command injection possible if builder name is controlled
buildx_setup_cmd <- "docker buildx create --name starburst-builder ..."
system(buildx_setup_cmd, ...)
```

**Impact:**
- Potential command injection
- Unvalidated input to shell
- Security risk if any params come from user/external source

**Fix Required:**
- Always use `shQuote()` for all user-provided values
- Prefer `system2()` with args vector over `system()` with command string
- Validate all inputs before passing to shell

**Priority:** **HIGH**

---

## 🔴 CRITICAL FUNCTIONAL ISSUES

### 4. **Race Condition in Manifest Updates** ⚠️ MEDIUM

**(Already documented in detached sessions report)**

**Location:** `R/session-state.R:78-118`

---

### 5. **No Timeout on S3 Downloads in Worker** ⚠️ HIGH

**Location:** `inst/templates/worker.R:29-37`

**Issue:** S3 downloads have no timeout. If S3 is slow/unreachable, worker hangs forever.

```r
s3$download_file(
  Bucket = bucket,
  Key = task_key,
  Filename = task_file
)  # No timeout!
```

**Impact:**
- Workers can hang indefinitely
- No way to recover
- Wastes compute resources
- No alerting

**Fix Required:**
```r
# Set timeout in paws config
s3 <- paws.storage::s3(config = list(
  region = region,
  connect_timeout = 60,
  timeout = 300  # 5 minutes
))
```

**Priority:** **HIGH**

---

### 6. **No Validation of Worker Count** ⚠️ MEDIUM

**Location:** `R/starburst-map.R:33-41`

**Issue:** No maximum limit on workers. User could accidentally request 10,000 workers.

```r
starburst_map <- function(.x, .f, workers = 10, ...) {
  validate_workers(workers)  # What does this actually check?
  // ...
}
```

Checking `validate_workers()`:
```r
validate_workers <- function(workers) {
  if (!is.numeric(workers) || workers < 1) {
    stop("workers must be a positive number")
  }
  # NO UPPER LIMIT!
}
```

**Impact:**
- User could accidentally create massive AWS bills
- No protection against typos (workers = 10000 instead of 100)
- Quota exhaustion
- Account limits hit

**Fix Required:**
```r
validate_workers <- function(workers) {
  if (!is.numeric(workers) || workers < 1) {
    stop("workers must be a positive number")
  }
  if (workers > 500) {
    stop("Maximum 500 workers allowed. For larger scale:\n",
         "  1. Ensure you have quota\n",
         "  2. Use workers = min(500, your_quota)\n",
         "  3. Consider batching your workload")
  }
}
```

**Priority:** **MEDIUM** (prevents user errors and runaway costs)

---

## 🟡 HIGH PRIORITY ISSUES

### 7. **Debug Logging in Production** ⚠️ LOW

**(Already documented)**

**Locations:** `R/plan-starburst.R:42,241,255,261,270`

**Fix:** Remove all DEBUG statements

---

### 8. **No CloudWatch Logging for Detached Sessions** ⚠️ HIGH

**(Already documented in detached sessions report)**

---

### 9. **Incomplete Cleanup Implementation** ⚠️ HIGH

**(Already documented in detached sessions report)**

---

### 10. **No Progress Reporting During Docker Builds** ⚠️ MEDIUM

**Location:** `R/utils.R:900-920`

**Issue:** Docker builds can take 20+ minutes with no progress updates. User sees nothing.

**Current:**
```r
cat_info("   • Building multi-platform base image: %s\n", image_tag)
build_result <- system(build_cmd)  # Silent for 20 minutes!
```

**Impact:**
- Poor UX
- Users think it's frozen
- No indication of progress
- Difficult to debug hangs

**Fix Required:**
```r
cat_info("   • Building multi-platform base image...\n")
cat_info("     This may take 15-20 minutes for first build\n")
cat_info("     Progress:\n")

# Stream output
build_result <- system(build_cmd, intern = FALSE)  # Show output
```

**Priority:** **MEDIUM** (UX issue)

---

### 11. **No Result Size Validation** ⚠️ MEDIUM

**(Already documented in detached sessions report)**

---

### 12. **Insufficient Error Context** ⚠️ MEDIUM

**Location:** Throughout codebase

**Issue:** Many error messages lack context about what was being attempted.

**Examples:**
```r
# R/setup.R:888
stop("Failed to get ECR authorization token")
# Which region? Which account?

# R/utils.R:923
stop("Docker buildx build failed")
# What image? What error? What command?

# R/future-starburst.R:70
stop("No starburst backend found. Call plan(starburst, ...) first.")
# What plan is currently active?
```

**Impact:**
- Difficult to debug
- Users can't self-help
- Support burden increases

**Fix Required:** Add context to all error messages:
```r
stop(sprintf("Failed to get ECR authorization token for account %s in region %s",
            account_id, region))

stop(sprintf("Docker buildx build failed for image %s\nCommand: %s\nCheck Docker logs",
            image_tag, build_cmd))
```

**Priority:** **MEDIUM**

---

## 🟢 MEDIUM PRIORITY ISSUES

### 13. **No Retry Logic for Transient Failures** ⚠️ MEDIUM

**Location:** Throughout AWS API calls

**Issue:** No retry logic for transient AWS API failures (throttling, timeouts, etc.)

**Examples:**
```r
# R/utils.R - S3 operations
s3$put_object(...)  # No retry
s3$download_file(...)  # No retry

# R/setup.R - ECR operations
ecr$get_authorization_token()  # No retry
```

**Impact:**
- Intermittent failures
- Users retry manually
- Poor reliability
- Wasted time

**Fix Required:** Implement exponential backoff retry wrapper:
```r
with_retry <- function(expr, max_attempts = 3, base_delay = 1) {
  for (attempt in 1:max_attempts) {
    result <- tryCatch(expr, error = function(e) e)

    if (!inherits(result, "error")) {
      return(result)
    }

    if (attempt < max_attempts) {
      delay <- base_delay * (2 ^ (attempt - 1))
      Sys.sleep(delay)
    } else {
      stop(result)
    }
  }
}

# Usage:
with_retry({
  s3$put_object(...)
})
```

**Priority:** **MEDIUM**

---

### 14. **No Disk Space Checks** ⚠️ MEDIUM

**Location:** Docker build operations

**Issue:** No check for available disk space before Docker builds. Builds require 5-10 GB.

**Impact:**
- Builds fail partway through
- Cryptic error messages
- Wasted time
- System instability

**Fix Required:**
```r
check_disk_space <- function(required_gb = 10) {
  # Check available space
  if (.Platform$OS.type == "unix") {
    df_output <- system("df -h . | tail -1", intern = TRUE)
    # Parse and check
  }
  # If insufficient, warn user
}
```

**Priority:** **MEDIUM**

---

### 15. **No Concurrent starburst_map() Protection** ⚠️ LOW

**Location:** `R/starburst-map.R`

**Issue:** If user calls `starburst_map()` twice concurrently, both try to modify the same S3 bucket/tasks.

**Impact:**
- File collisions
- Undefined behavior
- Potential data corruption

**Fix Required:** Add lock file or session isolation:
```r
starburst_map <- function(...) {
  # Create unique session ID
  session_id <- sprintf("map-%s", uuid::UUIDgenerate())

  # Use session-specific S3 prefix
  task_prefix <- sprintf("sessions/%s/", session_id)
  // ...
}
```

**Priority:** **LOW** (edge case)

---

### 16. **Memory Leaks in Long-Running Sessions** ⚠️ MEDIUM

**Location:** `R/future-starburst.R`, `R/starburst-map.R`

**Issue:** Future objects accumulate in memory. No cleanup after collection.

**Impact:**
- Memory grows unbounded in long sessions
- Can cause OOM errors
- Poor performance

**Fix Required:** Explicit cleanup after result collection:
```r
# After collecting results
rm(futures)
gc()  # Force garbage collection
```

**Priority:** **MEDIUM**

---

## 📚 DOCUMENTATION ISSUES

### 17. **No Troubleshooting Guide** ⚠️ HIGH

**(Already documented)**

**Missing:**
- Common error messages and solutions
- Debug procedures
- CloudWatch log access
- Manual cleanup procedures
- Recovery from failed states

**Priority:** **HIGH**

---

### 18. **No Security Best Practices Guide** ⚠️ HIGH

**Missing:**
- IAM role recommendations
- Network security (VPC, security groups)
- Credential management
- S3 bucket policies
- Encryption at rest/in transit
- Audit logging

**Fix Required:** Create `docs/SECURITY.md`

**Priority:** **HIGH**

---

### 19. **No Architecture Documentation** ⚠️ MEDIUM

**Current:** `ARCHITECTURE.md` exists but may be outdated

**Missing:**
- Current system diagram
- Data flow diagrams
- State machine diagrams (task lifecycle)
- Component interactions
- Failure modes and recovery

**Priority:** **MEDIUM**

---

### 20. **Insufficient Getting Started Guide** ⚠️ MEDIUM

**Issue:** `vignettes/getting-started.Rmd` is basic. Missing:
- Prerequisites check
- Common pitfalls
- First-time user walkthrough
- Verification steps
- What to expect

**Priority:** **MEDIUM**

---

### 21. **No Migration Path from Other Tools** ⚠️ LOW

**Missing:** Guides for migrating from:
- `parallel::parLapply()`
- `future::future_lapply()`
- AWS Batch
- Custom EC2 setups

**Priority:** **LOW**

---

### 22. **API Documentation Incomplete** ⚠️ MEDIUM

**(Already documented)**

**Many functions lack:**
- Parameter descriptions
- Return value documentation
- Examples
- See also references

**Priority:** **MEDIUM**

---

## 🧪 TESTING GAPS

### 23. **No Security Tests** ⚠️ HIGH

**Missing:**
- Test for password exposure
- Test for command injection vulnerabilities
- Test for S3 bucket permissions
- Test for IAM role assumptions

**Priority:** **HIGH**

---

### 24. **No Error Injection Tests** ⚠️ HIGH

**(Already documented)**

**Missing:**
- S3 failure scenarios
- ECS failure scenarios
- Network timeout scenarios
- Partial failure scenarios

**Priority:** **HIGH**

---

### 25. **No Load Tests** ⚠️ MEDIUM

**Missing:**
- 1000+ task tests
- 100+ worker tests
- Long-running session tests (12+ hours)
- Memory leak tests

**Priority:** **MEDIUM**

---

### 26. **No Integration Tests for setup()** ⚠️ MEDIUM

**Location:** `tests/testthat/`

**Issue:** No tests for `starburst_setup()`. Critical path untested.

**Missing:**
- VPC creation tests
- ECR setup tests
- IAM role tests
- Cleanup tests

**Priority:** **MEDIUM**

---

## 🏗️ CODE QUALITY ISSUES

### 27. **Inconsistent Error Handling Patterns** ⚠️ LOW

**Issue:** Mix of `stop()`, `warning()`, `cat_error()`, `tryCatch()` with no consistent pattern.

**Examples:**
```r
# Some functions use cat_error + stop
cat_error("Failed")
stop("Failed")

# Others just stop
stop("Failed")

# Some use tryCatch, some don't
```

**Fix Required:** Establish consistent error handling pattern:
```r
# Internal functions: use stop() with context
# User-facing functions: use cat_error() + stop()
# All AWS calls: wrap in tryCatch with retry
```

**Priority:** **LOW**

---

### 28. **Magic Numbers Throughout Code** ⚠️ LOW

**Examples:**
```r
# R/session-api.R:465
Sys.sleep(2)  # Why 2? Define as constant

# inst/templates/worker.R:111
idle_timeout <- 300  # Why 5 minutes? Should be configurable

# R/utils.R:920
--no-cache  # Always no cache? Should be conditional
```

**Fix Required:** Extract to named constants:
```r
POLL_INTERVAL_SECONDS <- 2
WORKER_IDLE_TIMEOUT_SECONDS <- 300
DOCKER_BUILD_USE_CACHE <- FALSE
```

**Priority:** **LOW**

---

### 29. **TODO/FIXME Comments Not Tracked** ⚠️ LOW

**Found:**
```r
# R/starburst-estimate.R:177
# TODO: Update these values from profiling results

# R/starburst-estimate.R:329
# TODO: Add region-specific pricing
```

**Issue:** TODOs not tracked in issue tracker. May be forgotten.

**Fix Required:**
- Create GitHub issues for all TODOs
- Reference issue number in code
- Or remove TODOs if not needed

**Priority:** **LOW**

---

## 📊 PERFORMANCE ISSUES

### 30. **No Connection Pooling for AWS Clients** ⚠️ LOW

**Issue:** New AWS client created for every operation:

```r
get_s3_client <- function(region) {
  paws.storage::s3(config = list(region = region))  # New client every time!
}
```

**Impact:**
- Slower operations
- More memory
- More API calls

**Fix Required:** Cache clients:
```r
.aws_clients <- new.env(parent = emptyenv())

get_s3_client <- function(region) {
  key <- paste0("s3_", region)
  if (!exists(key, envir = .aws_clients)) {
    .aws_clients[[key]] <- paws.storage::s3(config = list(region = region))
  }
  .aws_clients[[key]]
}
```

**Priority:** **LOW** (optimization)

---

### 31. **Inefficient Task Status Polling** ⚠️ LOW

**Location:** `R/session-api.R:400-465`

**Issue:** Polls ALL task statuses every 2 seconds. With 1000 tasks = 500 S3 API calls/second.

**Impact:**
- S3 request costs
- Potential throttling
- Slow collection

**Fix Required:**
- Track completed tasks, don't re-check
- Increase poll interval as completion approaches
- Use S3 event notifications instead of polling

**Priority:** **LOW**

---

## 🎯 FEATURE GAPS

### 32. **No Cost Alerts** ⚠️ MEDIUM

**Issue:** `starburst_config(max_cost_per_job = 10)` exists but not enforced.

**Missing:**
- Real-time cost tracking
- Automatic job termination at limit
- Cost alerts

**Priority:** **MEDIUM**

---

### 33. **No Worker Health Monitoring** ⚠️ MEDIUM

**Missing:**
- Worker heartbeats
- Stuck worker detection
- Automatic worker replacement
- Health dashboard

**Priority:** **MEDIUM**

---

### 34. **No Task Prioritization** ⚠️ LOW

**Issue:** All tasks treated equally. Can't prioritize urgent tasks.

**Missing:**
- Priority queue
- Task dependencies
- Task cancellation

**Priority:** **LOW**

---

## 📋 SUMMARY

### Critical (Fix Immediately):
1. 🚨 **ECR password exposed in shell command** - SECURITY
2. 🚨 **No error handling in worker task execution** - CRASHES
3. 🚨 **Unsafe system() calls** - SECURITY

### High Priority (Fix Soon):
4. No S3 timeout in workers
5. No CloudWatch logging
6. Incomplete cleanup
7. No troubleshooting guide
8. No security guide
9. No security tests
10. No error injection tests

### Medium Priority:
11. Race condition in manifest updates
12. No worker count validation
13. No result size validation
14. Insufficient error context
15. No retry logic
16. No disk space checks
17. Memory leaks
18. Many documentation gaps
19. Missing architecture docs
20. No setup() integration tests

### Low Priority:
21. Debug logging
22. Progress indicators
23. Code quality improvements
24. Performance optimizations
25. Feature gaps

---

## 🎯 RECOMMENDATIONS

### Immediate Actions (Before Production):
1. **Fix security vulnerability in ECR auth** (2 hours)
2. **Add error handling to worker execution** (4 hours)
3. **Review and fix all system() calls** (4 hours)
4. **Add S3 timeouts** (2 hours)
5. **Enable CloudWatch logging** (4 hours)

**Total: ~2 days of focused work**

### Short Term (1-2 Weeks):
6. Create troubleshooting guide
7. Create security guide
8. Add comprehensive error handling
9. Add retry logic for AWS calls
10. Fix manifest race condition
11. Implement proper cleanup
12. Add validation limits

### Medium Term (1-2 Months):
13. Comprehensive testing (security, errors, load)
14. Documentation improvements
15. Performance optimizations
16. Additional features (monitoring, alerts)

---

## 🏆 OVERALL ASSESSMENT

### Strengths:
- ✅ Core architecture is solid
- ✅ Good test coverage for happy paths
- ✅ Well-structured codebase
- ✅ Good vignettes and examples
- ✅ Quota management is thoughtful

### Critical Weaknesses:
- ❌ **Security vulnerability with credentials**
- ❌ **Insufficient error handling**
- ❌ **Limited observability**
- ❌ **Documentation gaps**
- ❌ **Missing production hardening**

### Bottom Line:
**The project is ~70% production-ready.** Core functionality works well, but needs:
1. Security fixes (CRITICAL - 1 day)
2. Error handling (HIGH - 2 days)
3. Observability (HIGH - 1 day)
4. Documentation (MEDIUM - 1 week)
5. Testing hardening (MEDIUM - 1 week)

**Estimated time to production-ready: 2-3 weeks of focused work**

The foundation is excellent. The gaps are mostly in operational maturity, not architecture.
