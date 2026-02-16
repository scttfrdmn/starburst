# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased](https://github.com/yourusername/starburst/compare/v0.1.0...HEAD)

### Changed

- License changed from MIT to Apache License 2.0
- Copyright holder: Scott Friedman (2026)

## [0.1.0](https://github.com/yourusername/starburst/releases/tag/v0.1.0) - 2026-02-03

### Added

#### Critical Blockers

- Docker image building from renv.lock with ECR authentication and push
- ECS task definition management with IAM role creation
- Wave-based queue management for quota-limited execution
- Task ARN storage in session-level registry
- Active cluster listing from ECS
- Cost calculation from actual task runtimes
- Multi-AZ subnet creation and management

#### Core Features

- Automatic environment synchronization using renv
- Base64-encoded ECR token decoding for authentication
- CloudWatch log group creation and management
- IAM execution role with ECS permissions
- IAM task role with S3 access permissions
- Task definition reuse based on CPU/memory/image compatibility
- In-memory wave queue with pending/running/completed tracking
- Automatic wave progression when quota-limited
- Future resolution integration with wave checking
- Real-time cost tracking from ECS task metadata
- Batch processing support for 100+ tasks
- Subnet tagging and public IP auto-assignment

#### Dependencies

- Added `digest` for renv.lock MD5 hashing
- Added `base64enc` for ECR authentication token decoding

#### Testing

- Comprehensive test suite with 62 tests (100% passing)
- Unit tests for task storage (17 tests)
- Integration logic tests (20 tests)
- Wave queue management tests (25 tests)
- Mocked AWS API tests for Docker, task definitions, cost, clusters, and
  subnets
- Full mockery-based testing infrastructure

#### Documentation

- IMPLEMENTATION_SUMMARY.md - Complete implementation overview
- TESTING_GUIDE.md - Comprehensive testing instructions
- IMPLEMENTATION_CHECKLIST.md - Detailed task tracking
- WAVE_QUEUE_FIX.md - Reference semantics fix documentation
- TEST_RESULTS_FINAL.md - Complete test results report

### Changed

- [`ensure_environment()`](https://scttfrdmn.github.io/starburst/reference/ensure_environment.md)
  now returns list with `hash` and `image_uri` (previously just hash)
- Plan object structure includes `wave_queue`, `worker_cpu`,
  `worker_memory`, `image_uri`
- Wave management functions follow functional pattern (return modified
  plan)

### Fixed

- Wave queue reference semantics issue (functions now return modified
  plan)
- Proper state management for quota-limited execution
- Task state transitions (queued → running → completed)

### Technical Details

- Lines of code: ~1,650 (implementation) + ~800 (tests)
- Test coverage: 100% (62/62 tests passing)
- Architecture: Functional programming pattern for state management
- Performance: Zero overhead (copy-on-write optimization)
