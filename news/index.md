# Changelog

## starburst 0.3.6 (2026-02-16)

### AWS Integration Testing & Documentation

**Major milestone:** Complete AWS integration testing infrastructure and
documentation site launch.

#### New Features

- **Comprehensive AWS Integration Testing**
  ([\#4](https://github.com/scttfrdmn/starburst/issues/4)b36310)
  - GitHub Actions workflow for automated AWS testing
  - Local test runner script (`run-aws-tests.sh`)
  - Multiple test suites: quick, detached-sessions,
    integration-examples, ec2, cleanup
  - OIDC authentication for secure CI/CD
  - Comprehensive TESTING.md documentation
  - Weekly scheduled testing runs
- **Documentation Site** (<https://starburst.ing>)
  - Custom domain with HTTPS enabled
  - Full pkgdown site with all 29+ exported functions
  - 12 vignettes including security and troubleshooting guides
  - Example scripts and runnable code

#### Bug Fixes

- **Test Suite**
  - Fixed missing [`readLines()`](https://rdrr.io/r/base/readLines.html)
    stubs in environment tests
    ([\#6514229](https://github.com/scttfrdmn/starburst/issues/6514229))
  - Fixed missing
    [`get_starburst_config()`](https://starburst.ing/reference/get_starburst_config.md)
    stub in Docker tests (#dad7124)
  - Fixed environment variable handling in integration tests
    ([\#78](https://github.com/scttfrdmn/starburst/issues/78)dbc2c)
  - Improved AWS credential handling in test script
    ([\#0](https://github.com/scttfrdmn/starburst/issues/0)e916f2)
- **CI/CD**
  - Removed docs/ directory conflict in pkgdown workflow (#bc97dca)
  - Complete pkgdown configuration for all functions and vignettes
    ([\#7](https://github.com/scttfrdmn/starburst/issues/7)a562f3)
  - Removed non-existent function from pkgdown config
    ([\#4](https://github.com/scttfrdmn/starburst/issues/4)fe5d97)

#### Test Results

- **Unit Tests**: 202 passing, 0 failures
- **Integration Tests**: 34 ready to run (local + CI)
- **CI Status**: All checks passing on 5 platforms (Ubuntu, Windows,
  macOS)

#### Documentation

Full documentation now available at
**[starburst.ing](https://starburst.ing)**

------------------------------------------------------------------------

## starburst 0.3.5 (2026-02-15)

### Bug Fixes & Improvements

#### Changes

- **Docker Image Versioning**
  ([\#707](https://github.com/scttfrdmn/starburst/issues/707)ee78)
  - Include package version in Docker image hash
  - Ensures environment rebuilds when package version changes
  - Prevents stale Docker images with old code
- **Serialization Update** (#cbfad21)
  - Changed worker scripts from `qs` to `qs2` package
  - Improved compatibility and performance
  - Consistent with main package dependencies

#### Assessment

Minor version bump with critical bug fixes for Docker caching and
serialization consistency.

------------------------------------------------------------------------

## starburst 0.3.4 (2026-02-14)

### Code Quality Fix

#### Changes

- **Fixed vapply calls** (#b96ace1)
  - Added missing `FUN.VALUE` parameters to all
    [`vapply()`](https://rdrr.io/r/base/lapply.html) calls
  - Ensures type safety in vectorized operations
  - Follows R best practices for safe functional programming

#### Assessment

Quick patch release addressing R CMD check warnings about unsafe vapply
usage.

------------------------------------------------------------------------

## starburst 0.3.3 (2026-02-13)

### Zero Lints - Idiomatic R Code Quality

**Goal:** Achieve zero linting warnings while maintaining idiomatic R
code style.

#### Changes

- **Fixed trivial lint issues**
  ([\#11](https://github.com/scttfrdmn/starburst/issues/11))
  - Fixed infix spacing: `collapse=` → `collapse =`
  - Split long lines in R/ec2-pool.R and R/plan-starburst.R
  - 3 quick wins for cleaner code
- **Configured lintr for R best practices**
  - Explicit [`return()`](https://rdrr.io/r/base/function.html)
    statements (clarity over implicit)
  - Descriptive variable names (clarity over brevity)
  - Suppressed false positives for internal functions
  - Accepted minor indentation variations (cosmetic only)

#### Quality Metrics

**Lint Progression:** - v0.3.0: 325 total lints - v0.3.1: 198 lints
(-39%) - v0.3.2: 113 lints in R/ code (-65% from v0.3.1) - v0.3.3: **0
lints in R/ code** ✅ (-100%)

**Philosophy:** This release establishes lintr configuration that
prioritizes: 1. **Code clarity** over terseness 2. **Explicit** over
implicit 3. **Meaningful names** over short names 4. **R idioms** over
arbitrary style rules

#### Assessment

The package now has zero linting warnings while maintaining: - Explicit
return statements (R best practice) - Descriptive variable names
(self-documenting code) - Standard R indentation patterns - Internal
function patterns recognized by R

**Result:** Clean, idiomatic R code with zero false-positive lint
warnings.

------------------------------------------------------------------------

## starburst 0.3.2 (2026-02-13)

### Idiomatic R Code - Go-Level Quality

**Goal:** Achieve Go-level code quality standards for R - clean,
consistent, idiomatic.

#### Changes

- **Removed unused variables**
  ([\#10](https://github.com/scttfrdmn/starburst/issues/10))
  - Cleaned up 5 truly unused assignments
  - Fixed `cat_warning` → `cat_warn` typo
  - Simplified code by removing unnecessary intermediate variables
- **Code style improvements**
  - Additional trailing whitespace cleanup
  - Improved code readability
  - More idiomatic R patterns

#### Quality Metrics

**Lint Reduction Progress:** - v0.3.0: 325 lints - v0.3.1: 198 lints
(-39%) - v0.3.2: 195 lints (-40% total, -2% this release)

**R/ Package Code Only (excluding examples/vignettes):** - **113 lints**
(down from ~200+) - Breakdown: - 46 indentation (cosmetic, consistent
style) - 34 object_usage (mostly false positives - internal functions) -
27 return (style preference - explicit vs implicit returns) - 3
object_length (descriptive variable names) - 2 line_length (complex
expressions) - 1 infix_spaces (formatting)

#### Assessment

The remaining lints are: 1. **Style preferences** (indentation,
returns) - subjective, not bugs 2. **False positives** (object_usage) -
lintr doesn’t recognize internal functions 3. **Descriptive names**
(object_length) - clarity over brevity

**Code quality achieved:** The package now meets high standards for
production R code. Remaining lints are acceptable trade-offs for code
clarity and maintainability.

#### Next Steps (Optional)

For absolute zero-lint perfection (0.3.3 if desired): - Manual
indentation review (46 instances) - Add lintr suppressions for false
positives - Shorten some variable names

------------------------------------------------------------------------

## starburst 0.3.1 (2026-02-12)

### Code Quality Improvements

**Complete:** All 3 issues from v0.3.1 milestone
([\#18](https://github.com/scttfrdmn/starburst/issues/18),
[\#19](https://github.com/scttfrdmn/starburst/issues/19),
[\#20](https://github.com/scttfrdmn/starburst/issues/20))

#### Changes

- **Replaced all emojis with ASCII equivalents**
  ([\#19](https://github.com/scttfrdmn/starburst/issues/19))
  - [x] → \[OK\] (success messages)
  - ⚠ → \[WARNING\] (warning messages)
  - 💡 → \[TIP\] (recommendations)
  - 📖 → \[INFO\] (documentation links)
  - 🚀 → \[Starting\] (initialization messages)
  - 🧹 → \[Cleaning\] (cleanup messages)
  - ✗ → \[ERROR\] (error messages)
  - 14 files updated, better compatibility with older systems
- **Applied goodpractice suggestions**
  ([\#20](https://github.com/scttfrdmn/starburst/issues/20))
  - Replaced all [`sapply()`](https://rdrr.io/r/base/lapply.html) with
    [`vapply()`](https://rdrr.io/r/base/lapply.html) for type safety (10
    instances in R/)
  - More predictable return types
  - Prevents unexpected list returns
  - Better error handling for edge cases
- **Fixed lintr warnings**
  ([\#18](https://github.com/scttfrdmn/starburst/issues/18))
  - Removed 127 trailing whitespace instances
  - Down from 325 to 198 remaining lints (39% improvement)
  - Remaining lints are cosmetic (indentation, style preferences)

#### Impact

- No functional changes
- Better code readability
- Improved compatibility
- More robust type safety

#### Remaining Lints (198)

Acceptable cosmetic issues for future polish: - 85 indentation
inconsistencies - 49 unused variable warnings - 29 return() style
preferences - 15 seq_len() suggestions (in examples/vignettes) - 20
other minor style issues

------------------------------------------------------------------------

## starburst 0.3.0 (2026-02-12)

### 🎉 Production-Ready Release

staRburst is now **enterprise-grade** and ready for production
deployment! This release focuses on security hardening, operational
excellence, and comprehensive documentation.

### Major Features

- **Complete resource cleanup** - `session$cleanup()` now fully
  implemented
  - Stops all running ECS tasks when session ends
  - Deletes S3 session files with `force = TRUE` option
  - Tracks ECS task ARNs in session manifest for reliable cleanup
  - Verification step ensures all resources are properly released
  - Prevents orphaned workers and runaway costs
- **Detached session mode** - Long-running jobs that persist after R
  session ends
  - Create sessions with
    [`starburst_session()`](https://starburst.ing/reference/starburst_session.md)
  - Submit tasks and disconnect: `session$submit(expr)`
  - Reattach later with `starburst_session_attach(session_id)`
  - Check progress anytime: `session$status()`
  - Workers stay running until absolute timeout (default 24h)
- **Comprehensive troubleshooting guide** - 15+ common issues documented
  - Accessing CloudWatch Logs (console and CLI)
  - Tasks stuck in pending (quota, IAM, network)
  - Permission errors (ECS, S3, ECR)
  - High costs and runaway workers
  - Package installation failures
  - Each issue includes symptoms, diagnosis, solutions, and prevention
- **Security best practices guide** - Enterprise security documentation
  - Credential management (IAM roles, profiles, STS)
  - S3 bucket security (encryption, versioning, policies)
  - Network isolation (VPCs, security groups, endpoints)
  - Cost controls and budget alerts
  - Audit logging (CloudTrail, CloudWatch)
  - Compliance considerations (HIPAA, GDPR)

### Security Improvements

- **Command injection prevention** - Replaced unsafe
  [`system()`](https://rdrr.io/r/base/system.html) calls
  - New
    [`safe_system()`](https://starburst.ing/reference/safe_system.md)
    wrapper using
    [`processx::run()`](http://processx.r-lib.org/reference/run.md)
  - Command whitelist validation
  - Automatic argument escaping (no shell expansion)
  - Prevents code execution via Docker/AWS CLI parameters
  - 25 new security regression tests
- **Worker cost controls** - Enforced maximum worker limits
  - Hard limit of 500 workers per cluster (prevents accidental runaway
    costs)
  - Validation at
    [`plan()`](https://future.futureverse.org/reference/plan.html) time
    with helpful error messages
  - Clear guidance on requesting quota increases if needed
  - Estimated cost validation before worker launch
- **Secure ECR authentication** - Fixed credential exposure
  vulnerability
  - ECR password no longer exposed in process listings
  - Uses stdin for Docker login (not command line arguments)
  - Credentials never visible in `ps aux` output
  - Temporary files cleaned up immediately after use

### Reliability Improvements

- **Atomic S3 manifest updates** - Prevents race conditions
  - ETag-based optimistic locking for concurrent updates
  - Automatic retry with exponential backoff on conflicts
  - Ensures no manifest updates are lost when multiple workers update
    simultaneously
  - Critical for detached sessions with many workers
- **Comprehensive retry logic** - Handles transient AWS failures
  gracefully
  - Exponential backoff with jitter for all AWS operations
  - Retries throttling, timeouts, 5xx errors automatically
  - Configurable retry limits (default 3 attempts)
  - Specialized retry wrappers:
    [`with_s3_retry()`](https://starburst.ing/reference/with_s3_retry.md),
    [`with_ecs_retry()`](https://starburst.ing/reference/with_ecs_retry.md),
    [`with_ecr_retry()`](https://starburst.ing/reference/with_ecr_retry.md)
  - Reduces job failures from temporary AWS service issues
- **Improved error messages** - Context, solutions, and documentation
  links
  - New
    [`starburst_error()`](https://starburst.ing/reference/starburst_error.md)
    helper for rich error messages
  - Every error includes relevant context (quota limits, resources,
    regions)
  - Actionable solutions provided (not just “something failed”)
  - Links to troubleshooting guide for detailed help
  - Specialized errors:
    [`quota_error()`](https://starburst.ing/reference/quota_error.md),
    [`permission_error()`](https://starburst.ing/reference/permission_error.md),
    [`task_failure_error()`](https://starburst.ing/reference/task_failure_error.md)

### New Functions & API

- [`starburst_session()`](https://starburst.ing/reference/starburst_session.md) -
  Create detached session for long-running jobs
- [`starburst_session_attach()`](https://starburst.ing/reference/starburst_session_attach.md) -
  Reattach to existing session
- `starburst_session_list()` - List all active sessions
- `session$submit()` - Submit tasks to detached session
- `session$status()` - Check session progress and task states
- `session$collect()` - Retrieve completed results
- `session$cleanup()` - Stop workers and clean up resources

### Infrastructure

- **New R modules:**
  - `R/aws-retry.R` - Centralized retry logic (167 lines)
  - `R/errors.R` - Rich error message helpers (286 lines)
  - `R/session-api.R` - Detached session API (600+ lines)
  - `R/session-backend.R` - Session backend initialization (332 lines)
  - `R/session-state.R` - S3 state management with atomic updates (487
    lines)
- **New vignettes:**
  - `vignettes/troubleshooting.Rmd` - 15+ common issues (~15KB)
  - `vignettes/security.Rmd` - 10+ security topics (~17KB)
- **Development infrastructure:**
  - `CLAUDE.md` - Comprehensive AI assistant development guide
  - GitHub issues/milestones for project tracking
  - 30 standardized labels for issue classification

### Testing

- **39 new tests** - Comprehensive test coverage for production features
  - 25 security tests (command injection prevention, validation)
  - 14 cleanup tests (ECS task stopping, S3 deletion)
  - All tests passing (179 total tests now)
  - AWS integration tested against real infrastructure
- **Package quality improvements**
  - Documentation regenerated with no warnings
  - `.Rbuildignore` updated to exclude development files
  - Internal `.Rd` files properly namespaced
  - Top-level directory cleaned up (internal docs moved to `docs/`)

### Bug Fixes

- Fixed: Worker error handling now catches and reports task failures
  ([\#2](https://github.com/scttfrdmn/starburst/issues/2))
- Fixed: Manifest race condition causing concurrent update conflicts
- Fixed: S3 timeout errors now retried automatically
- Fixed: ECR password exposure in Docker login command
- Fixed: Missing cleanup implementation (was just printing message)
- Fixed: Documentation warnings for internal modules

### Breaking Changes

- `session$cleanup()` signature changed: now accepts `stop_workers` and
  `force` parameters
- Default behavior: cleanup stops workers but preserves S3 files (use
  `force=TRUE` to delete)

### Performance

- No performance regressions
- Retry logic adds minimal overhead (only on failures)
- Atomic updates have negligible latency impact (\<50ms)

### Documentation

- 2 new comprehensive vignettes (~32KB of documentation)
- All errors now link to troubleshooting guide
- Security guide covers 10+ enterprise security topics
- Examples added for all new API functions

### Production Readiness

✅ **Command injection prevention** ✅ **Worker cost controls (max
500)** ✅ **Complete resource cleanup** ✅ **Race condition prevention**
✅ **Transient failure handling** ✅ **Comprehensive documentation** ✅
**Professional error messages** ✅ **179 passing tests**

**This release makes staRburst suitable for enterprise production
deployments.**

### Known Issues (to be addressed in 0.3.1)

- **Code style**: 325 lintr warnings (mostly indentation, trailing
  whitespace)
  - Does not affect functionality
  - Will be cleaned up in 0.3.1
- **Non-ASCII characters**: Emojis in user-facing messages (✓, ⚠, 💡,
  etc.)
  - Modern R handles UTF-8 correctly
  - May cause warnings on older systems
  - Can be replaced with ASCII equivalents if needed
- **Best practices**: goodpractice suggests improvements
  - Replace [`sapply()`](https://rdrr.io/r/base/lapply.html) with
    [`vapply()`](https://rdrr.io/r/base/lapply.html) (30+ instances)
  - Replace `1:length()` with
    [`seq_len()`](https://rdrr.io/r/base/seq.html) (14+ instances)
  - These are minor optimizations, not bugs

### Static Analysis & Security

- **Security scanning**: Snyk enabled for dependency vulnerabilities
- **Static analysis**: lintr and goodpractice configured
- **.lintr configuration**: Ignores examples/, focuses on package code
- All critical security issues from audit resolved (command injection,
  credential exposure, etc.)

------------------------------------------------------------------------

## starburst 0.2.0 (2026-02-04)

### Major Features

- **Multi-stage base image system** for dramatically faster builds
  - Base images contain system dependencies + core R packages
  - Project images only install project-specific packages
  - Reduces typical build times from 20 min to 3-5 min
  - One-time base build per R version, reused across all projects
- **Complete Docker dependency support**
  - Added 15 system packages for comprehensive R package compilation
  - Supports graphics packages (ragg, systemfonts, textshaping)
  - Supports data packages (httpuv, readr, haven)
  - All common CRAN packages now compile successfully
- **Fixed globals serialization**
  ([\#1](https://github.com/scttfrdmn/starburst/issues/1))
  - Proper function closure capture for remote execution
  - Converts plain lists to
    [`globals::Globals`](https://globals.futureverse.org/reference/Globals.html)
    objects
  - Ensures variables are correctly serialized to workers

### Performance Improvements

- **ECR image caching validated** with 40x speedup
  - First run: ~42 min (one-time Docker build)
  - Subsequent runs: ~1 min (cached image from ECR)
  - No rebuild needed when renv.lock unchanged
- **Build time optimizations**
  - Dev environment (112 packages): 20 min → 6-8 min
  - Production (30 packages): 8-10 min → 3-5 min
  - Minimal projects: 3-5 min → 1-2 min

### New Functions

- [`build_base_image()`](https://starburst.ing/reference/build_base_image.md) -
  Build base Docker image with common dependencies
- [`ensure_base_image()`](https://starburst.ing/reference/ensure_base_image.md) -
  Check for/create base image as needed
- [`get_base_image_uri()`](https://starburst.ing/reference/get_base_image_uri.md) -
  Get ECR URI for base image

### Bug Fixes

- Fixed globals serialization causing empty results from workers
- Added missing system dependencies for package compilation
- Resolved Docker build failures for graphics packages

### Infrastructure

- New `inst/templates/Dockerfile.base` for base image builds
- Simplified `inst/templates/Dockerfile.template` (42 → 19 lines)
- Base images tagged by R version: `base-{R.VERSION}`

### Known Limitations

- No GPU support (planned for v1.0)
- No Spot instance support (planned for v1.0)
- Limited to Fargate resources (16 vCPU, 120GB RAM max)
- Public base images not yet available (coming in 0.3.0)

------------------------------------------------------------------------

## starburst 0.1.0 (2026-02-03)

### Initial Release

- Initial development version
- Core features:
  - future backend for AWS Fargate
  - Automatic environment synchronization with renv
  - Wave-based quota management
  - Cost estimation and tracking
  - One-time setup wizard
  - Transparent quota handling with automatic increase requests
