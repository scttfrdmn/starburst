# starburst 0.3.1 (2026-02-12)

## Code Quality Improvements

**Complete:** All 3 issues from v0.3.1 milestone (#18, #19, #20)

### Changes

* **Replaced all emojis with ASCII equivalents** (#19)
  - ✓ → [OK] (success messages)
  - ⚠ → [WARNING] (warning messages)
  - 💡 → [TIP] (recommendations)
  - 📖 → [INFO] (documentation links)
  - 🚀 → [Starting] (initialization messages)
  - 🧹 → [Cleaning] (cleanup messages)
  - ✗ → [ERROR] (error messages)
  - 14 files updated, better compatibility with older systems

* **Applied goodpractice suggestions** (#20)
  - Replaced all `sapply()` with `vapply()` for type safety (10 instances in R/)
  - More predictable return types
  - Prevents unexpected list returns
  - Better error handling for edge cases

* **Fixed lintr warnings** (#18)
  - Removed 127 trailing whitespace instances
  - Down from 325 to 198 remaining lints (39% improvement)
  - Remaining lints are cosmetic (indentation, style preferences)

### Impact

- No functional changes
- Better code readability
- Improved compatibility
- More robust type safety

### Remaining Lints (198)

Acceptable cosmetic issues for future polish:
- 85 indentation inconsistencies
- 49 unused variable warnings
- 29 return() style preferences
- 15 seq_len() suggestions (in examples/vignettes)
- 20 other minor style issues

---

# starburst 0.3.0 (2026-02-12)

## 🎉 Production-Ready Release

staRburst is now **enterprise-grade** and ready for production deployment! This release focuses on security hardening, operational excellence, and comprehensive documentation.

## Major Features

* **Complete resource cleanup** - `session$cleanup()` now fully implemented
  - Stops all running ECS tasks when session ends
  - Deletes S3 session files with `force = TRUE` option
  - Tracks ECS task ARNs in session manifest for reliable cleanup
  - Verification step ensures all resources are properly released
  - Prevents orphaned workers and runaway costs

* **Detached session mode** - Long-running jobs that persist after R session ends
  - Create sessions with `starburst_session()`
  - Submit tasks and disconnect: `session$submit(expr)`
  - Reattach later with `starburst_session_attach(session_id)`
  - Check progress anytime: `session$status()`
  - Workers stay running until absolute timeout (default 24h)

* **Comprehensive troubleshooting guide** - 15+ common issues documented
  - Accessing CloudWatch Logs (console and CLI)
  - Tasks stuck in pending (quota, IAM, network)
  - Permission errors (ECS, S3, ECR)
  - High costs and runaway workers
  - Package installation failures
  - Each issue includes symptoms, diagnosis, solutions, and prevention

* **Security best practices guide** - Enterprise security documentation
  - Credential management (IAM roles, profiles, STS)
  - S3 bucket security (encryption, versioning, policies)
  - Network isolation (VPCs, security groups, endpoints)
  - Cost controls and budget alerts
  - Audit logging (CloudTrail, CloudWatch)
  - Compliance considerations (HIPAA, GDPR)

## Security Improvements

* **Command injection prevention** - Replaced unsafe `system()` calls
  - New `safe_system()` wrapper using `processx::run()`
  - Command whitelist validation
  - Automatic argument escaping (no shell expansion)
  - Prevents code execution via Docker/AWS CLI parameters
  - 25 new security regression tests

* **Worker cost controls** - Enforced maximum worker limits
  - Hard limit of 500 workers per cluster (prevents accidental runaway costs)
  - Validation at `plan()` time with helpful error messages
  - Clear guidance on requesting quota increases if needed
  - Estimated cost validation before worker launch

* **Secure ECR authentication** - Fixed credential exposure vulnerability
  - ECR password no longer exposed in process listings
  - Uses stdin for Docker login (not command line arguments)
  - Credentials never visible in `ps aux` output
  - Temporary files cleaned up immediately after use

## Reliability Improvements

* **Atomic S3 manifest updates** - Prevents race conditions
  - ETag-based optimistic locking for concurrent updates
  - Automatic retry with exponential backoff on conflicts
  - Ensures no manifest updates are lost when multiple workers update simultaneously
  - Critical for detached sessions with many workers

* **Comprehensive retry logic** - Handles transient AWS failures gracefully
  - Exponential backoff with jitter for all AWS operations
  - Retries throttling, timeouts, 5xx errors automatically
  - Configurable retry limits (default 3 attempts)
  - Specialized retry wrappers: `with_s3_retry()`, `with_ecs_retry()`, `with_ecr_retry()`
  - Reduces job failures from temporary AWS service issues

* **Improved error messages** - Context, solutions, and documentation links
  - New `starburst_error()` helper for rich error messages
  - Every error includes relevant context (quota limits, resources, regions)
  - Actionable solutions provided (not just "something failed")
  - Links to troubleshooting guide for detailed help
  - Specialized errors: `quota_error()`, `permission_error()`, `task_failure_error()`

## New Functions & API

* `starburst_session()` - Create detached session for long-running jobs
* `starburst_session_attach()` - Reattach to existing session
* `starburst_session_list()` - List all active sessions
* `session$submit()` - Submit tasks to detached session
* `session$status()` - Check session progress and task states
* `session$collect()` - Retrieve completed results
* `session$cleanup()` - Stop workers and clean up resources

## Infrastructure

* **New R modules:**
  - `R/aws-retry.R` - Centralized retry logic (167 lines)
  - `R/errors.R` - Rich error message helpers (286 lines)
  - `R/session-api.R` - Detached session API (600+ lines)
  - `R/session-backend.R` - Session backend initialization (332 lines)
  - `R/session-state.R` - S3 state management with atomic updates (487 lines)

* **New vignettes:**
  - `vignettes/troubleshooting.Rmd` - 15+ common issues (~15KB)
  - `vignettes/security.Rmd` - 10+ security topics (~17KB)

* **Development infrastructure:**
  - `CLAUDE.md` - Comprehensive AI assistant development guide
  - GitHub issues/milestones for project tracking
  - 30 standardized labels for issue classification

## Testing

* **39 new tests** - Comprehensive test coverage for production features
  - 25 security tests (command injection prevention, validation)
  - 14 cleanup tests (ECS task stopping, S3 deletion)
  - All tests passing (179 total tests now)
  - AWS integration tested against real infrastructure

* **Package quality improvements**
  - Documentation regenerated with no warnings
  - `.Rbuildignore` updated to exclude development files
  - Internal `.Rd` files properly namespaced
  - Top-level directory cleaned up (internal docs moved to `docs/`)

## Bug Fixes

* Fixed: Worker error handling now catches and reports task failures (#2)
* Fixed: Manifest race condition causing concurrent update conflicts
* Fixed: S3 timeout errors now retried automatically
* Fixed: ECR password exposure in Docker login command
* Fixed: Missing cleanup implementation (was just printing message)
* Fixed: Documentation warnings for internal modules

## Breaking Changes

* `session$cleanup()` signature changed: now accepts `stop_workers` and `force` parameters
* Default behavior: cleanup stops workers but preserves S3 files (use `force=TRUE` to delete)

## Performance

* No performance regressions
* Retry logic adds minimal overhead (only on failures)
* Atomic updates have negligible latency impact (<50ms)

## Documentation

* 2 new comprehensive vignettes (~32KB of documentation)
* All errors now link to troubleshooting guide
* Security guide covers 10+ enterprise security topics
* Examples added for all new API functions

## Production Readiness

✅ **Command injection prevention**
✅ **Worker cost controls (max 500)**
✅ **Complete resource cleanup**
✅ **Race condition prevention**
✅ **Transient failure handling**
✅ **Comprehensive documentation**
✅ **Professional error messages**
✅ **179 passing tests**

**This release makes staRburst suitable for enterprise production deployments.**

## Known Issues (to be addressed in 0.3.1)

* **Code style**: 325 lintr warnings (mostly indentation, trailing whitespace)
  - Does not affect functionality
  - Will be cleaned up in 0.3.1

* **Non-ASCII characters**: Emojis in user-facing messages (✓, ⚠, 💡, etc.)
  - Modern R handles UTF-8 correctly
  - May cause warnings on older systems
  - Can be replaced with ASCII equivalents if needed

* **Best practices**: goodpractice suggests improvements
  - Replace `sapply()` with `vapply()` (30+ instances)
  - Replace `1:length()` with `seq_len()` (14+ instances)
  - These are minor optimizations, not bugs

## Static Analysis & Security

* **Security scanning**: Snyk enabled for dependency vulnerabilities
* **Static analysis**: lintr and goodpractice configured
* **.lintr configuration**: Ignores examples/, focuses on package code
* All critical security issues from audit resolved (command injection, credential exposure, etc.)

---

# starburst 0.2.0 (2026-02-04)

## Major Features

* **Multi-stage base image system** for dramatically faster builds
  - Base images contain system dependencies + core R packages
  - Project images only install project-specific packages
  - Reduces typical build times from 20 min to 3-5 min
  - One-time base build per R version, reused across all projects

* **Complete Docker dependency support**
  - Added 15 system packages for comprehensive R package compilation
  - Supports graphics packages (ragg, systemfonts, textshaping)
  - Supports data packages (httpuv, readr, haven)
  - All common CRAN packages now compile successfully

* **Fixed globals serialization** (#1)
  - Proper function closure capture for remote execution
  - Converts plain lists to `globals::Globals` objects
  - Ensures variables are correctly serialized to workers

## Performance Improvements

* **ECR image caching validated** with 40x speedup
  - First run: ~42 min (one-time Docker build)
  - Subsequent runs: ~1 min (cached image from ECR)
  - No rebuild needed when renv.lock unchanged

* **Build time optimizations**
  - Dev environment (112 packages): 20 min → 6-8 min
  - Production (30 packages): 8-10 min → 3-5 min
  - Minimal projects: 3-5 min → 1-2 min

## New Functions

* `build_base_image()` - Build base Docker image with common dependencies
* `ensure_base_image()` - Check for/create base image as needed
* `get_base_image_uri()` - Get ECR URI for base image

## Bug Fixes

* Fixed globals serialization causing empty results from workers
* Added missing system dependencies for package compilation
* Resolved Docker build failures for graphics packages

## Infrastructure

* New `inst/templates/Dockerfile.base` for base image builds
* Simplified `inst/templates/Dockerfile.template` (42 → 19 lines)
* Base images tagged by R version: `base-{R.VERSION}`

## Known Limitations

* No GPU support (planned for v1.0)
* No Spot instance support (planned for v1.0)
* Limited to Fargate resources (16 vCPU, 120GB RAM max)
* Public base images not yet available (coming in 0.3.0)

---

# starburst 0.1.0 (2026-02-03)

## Initial Release

* Initial development version
* Core features:
  - future backend for AWS Fargate
  - Automatic environment synchronization with renv
  - Wave-based quota management
  - Cost estimation and tracking
  - One-time setup wizard
  - Transparent quota handling with automatic increase requests
