# Plan: Remove Fargate Support from staRburst

## Executive Summary

**Goal**: Simplify codebase by removing Fargate support, keeping only EC2.

**Rationale**:
- EC2 has **much faster cold start** (<30s vs 10+ min)
- EC2 provides **instance type control** (Graviton, spot, etc.)
- EC2 is **more cost-effective** for burst workloads
- Fargate adds complexity without clear benefits for this use case

**Impact**: Breaking change - users on Fargate will need to migrate to EC2

---

## Migration Strategy

### For Users

**Before removal**:
```r
# OLD: Fargate (default)
plan(starburst, workers = 50)

# OLD: Explicit Fargate
plan(starburst, workers = 50, launch_type = "FARGATE")
```

**After removal**:
```r
# NEW: EC2 only (simpler API)
plan(starburst, workers = 50, instance_type = "c6a.large")

# Or with defaults
plan(starburst, workers = 50)  # Uses default instance type
```

**Migration steps for users**:
1. Run `starburst_setup_ec2()` (one-time)
2. Add `instance_type` parameter to `plan()` calls
3. Remove `launch_type = "FARGATE"` if present
4. Rebuild Docker images (happens automatically)

---

## Changes Required

### 1. API Simplification

**File**: `R/plan-starburst.R`

**Remove parameters**:
- `launch_type` (always EC2 now)

**Add default**:
- `instance_type = "c6a.large"` (default to common x86 instance)

**Before**:
```r
plan.starburst <- function(strategy,
                           workers = 10,
                           cpu = 4,
                           memory = "8GB",
                           region = NULL,
                           timeout = 3600,
                           launch_type = "FARGATE",  # REMOVE
                           instance_type = "c7g.xlarge",
                           use_spot = FALSE,
                           warm_pool_timeout = 3600,
                           ...) {
```

**After**:
```r
plan.starburst <- function(strategy,
                           workers = 10,
                           instance_type = "c6a.large",  # Now required with default
                           use_spot = FALSE,
                           warm_pool_timeout = 3600,
                           region = NULL,
                           timeout = 3600,
                           ...) {
```

**Remove logic**:
- All `if (backend$launch_type == "FARGATE")` branches
- Fargate-specific configuration

### 2. Task Submission Simplification

**File**: `R/future-starburst.R`

**Remove**:
- `submit_fargate_task()` function (or rename to `submit_task()`)
- Fargate-specific run_task parameters
- All launch_type conditionals

**Before**:
```r
if (backend$launch_type == "EC2") {
  run_task_params$capacityProviderStrategy <- list(...)
} else {
  run_task_params$launchType <- "FARGATE"
}
```

**After**:
```r
# Always use EC2 capacity provider
run_task_params$capacityProviderStrategy <- list(
  list(
    capacityProvider = backend$capacity_provider_name,
    weight = 1
  )
)
```

### 3. Task Definition Simplification

**File**: `R/utils.R` (lines 810-912)

**Remove**:
- Fargate compatibility requirements
- Launch type conditionals

**Before**:
```r
if (plan$launch_type == "FARGATE") {
  task_def_params$requiresCompatibilities <- list("FARGATE")
} else if (plan$launch_type == "EC2") {
  task_def_params$requiresCompatibilities <- list("EC2")
  task_def_params$runtimePlatform <- list(...)
}
```

**After**:
```r
# Always EC2
task_def_params$requiresCompatibilities <- list("EC2")
task_def_params$runtimePlatform <- list(
  cpuArchitecture = plan$architecture,
  operatingSystemFamily = "LINUX"
)
```

### 4. Cost Estimation Simplification

**File**: `R/utils.R` (lines 213-231)

**Remove**:
- Fargate pricing
- Launch type conditionals

**Before**:
```r
estimate_cost <- function(workers, cpu, memory,
                         estimated_runtime_hours = 1,
                         launch_type = "FARGATE",
                         instance_type = NULL,
                         use_spot = FALSE) {
  if (launch_type == "FARGATE") {
    # Fargate pricing...
  } else {
    # EC2 pricing...
  }
}
```

**After**:
```r
estimate_cost <- function(workers,
                         instance_type,
                         estimated_runtime_hours = 1,
                         use_spot = FALSE) {
  # Only EC2 pricing
  instance_price <- get_ec2_instance_price(instance_type, use_spot)
  instances_needed <- ceiling(workers / get_instance_workers(instance_type))
  total_cost <- instances_needed * instance_price * estimated_runtime_hours

  list(
    per_instance = instance_price,
    instances_needed = instances_needed,
    total_estimated = total_cost
  )
}
```

### 5. Setup Simplification

**File**: `R/setup.R`

**Merge**:
- `starburst_setup()` and `starburst_setup_ec2()` into single function
- Always create EC2 infrastructure

**Before**:
```r
starburst_setup()        # For Fargate
starburst_setup_ec2()    # Additional for EC2
```

**After**:
```r
starburst_setup(instance_types = c("c6a.large", "c7g.xlarge"))
# Creates everything in one step
```

### 6. Cleanup Function Simplification

**File**: `R/plan-starburst.R` (cleanup_cluster)

**Remove**:
- Fargate cleanup branches
- Launch type conditionals

**Before**:
```r
cleanup_cluster <- function(backend) {
  # ... existing cleanup ...

  if (backend$launch_type == "EC2") {
    # EC2 pool timeout logic
  }
}
```

**After**:
```r
cleanup_cluster <- function(backend) {
  # ... existing cleanup ...

  # Always check pool timeout
  idle_time <- difftime(Sys.time(), backend$pool_started_at, units = "secs")
  if (idle_time > backend$warm_pool_timeout) {
    stop_warm_pool(backend)
  }
}
```

### 7. Backend State Simplification

**File**: `R/plan-starburst.R`

**Remove from backend object**:
- `launch_type` field

**Before**:
```r
backend <- list(
  cluster_name = cluster_name,
  region = region,
  launch_type = launch_type,  # REMOVE
  instance_type = instance_type,
  architecture = get_architecture_from_instance_type(instance_type),
  ...
)
```

**After**:
```r
backend <- list(
  cluster_name = cluster_name,
  region = region,
  instance_type = instance_type,
  architecture = get_architecture_from_instance_type(instance_type),
  capacity_provider_name = sprintf("starburst-%s", instance_type),
  asg_name = sprintf("starburst-asg-%s", instance_type),
  ...
)
```

---

## Documentation Updates

### Files to Update

1. **README.md**
   - Remove Fargate mentions
   - Update Quick Start to show EC2 only
   - Update examples to use instance_type

2. **vignettes/getting-started.Rmd**
   - Remove launch_type parameter from examples
   - Emphasize EC2 benefits
   - Update setup instructions

3. **AWS_COST_MODEL.md**
   - Remove Fargate pricing section
   - Focus on EC2 cost optimization
   - Update idle cost calculations

4. **All example files** (`examples/*.R`)
   - Remove `USE_STARBURST` env var logic
   - Always use instance_type parameter
   - Update cost estimates

5. **Test files**
   - Remove Fargate tests
   - Focus on EC2 integration tests
   - Update test-comparison.R to remove Fargate mode

---

## Breaking Changes Notice

**VERSION**: Will require bumping to v0.2.0

**CHANGELOG.md** entry:
```markdown
## v0.2.0 - BREAKING CHANGES

### Removed
- **Fargate support removed**: staRburst now uses EC2 exclusively for better performance and cost control
  - `launch_type` parameter removed from `plan()`
  - `starburst_setup_ec2()` merged into `starburst_setup()`

### Migration Guide
Existing users on Fargate must:
1. Run `starburst_setup()` to create EC2 infrastructure
2. Update `plan()` calls to include `instance_type` parameter
3. Rebuild Docker images (automatic on first run)

Example:
```r
# OLD
plan(starburst, workers = 50, launch_type = "FARGATE")

# NEW
plan(starburst, workers = 50, instance_type = "c6a.large")
```

### Why This Change?
- **10x faster cold start**: <30s vs 10+ min with Fargate
- **Better cost control**: Choose instance types and spot pricing
- **Simpler codebase**: Less complexity, easier to maintain
```

---

## Implementation Steps

### Phase 1: Preparation (1 day)
1. Create migration branch: `git checkout -b remove-fargate`
2. Add deprecation warnings in current version
3. Update docs with migration guide
4. Release v0.1.1 with warnings

### Phase 2: Core Removal (2 days)
1. Remove launch_type from plan.starburst()
2. Remove Fargate branches from submit_task()
3. Remove Fargate from task definitions
4. Simplify cleanup_cluster()
5. Update backend state

### Phase 3: Cost & Setup (1 day)
6. Simplify estimate_cost()
7. Merge setup functions
8. Update configuration

### Phase 4: Documentation (1 day)
9. Update README.md
10. Update all vignettes
11. Update examples
12. Update CHANGELOG.md

### Phase 5: Testing (1 day)
13. Update test suite
14. Remove Fargate tests
15. Run full benchmark suite
16. Verify all examples work

### Phase 6: Release (1 day)
17. Bump version to 0.2.0
18. Tag release
19. Update GitHub releases
20. Announce breaking change

**Total**: ~7 days

---

## Files to Modify

### R Files
- `R/plan-starburst.R` - Remove launch_type, simplify backend
- `R/future-starburst.R` - Remove Fargate task submission
- `R/utils.R` - Simplify cost estimation and task definitions
- `R/setup.R` - Merge setup functions
- `R/ec2-pool.R` - No changes needed (EC2-specific)

### Documentation
- `README.md`
- `vignettes/getting-started.Rmd`
- `vignettes/example-*.Rmd` (all)
- `AWS_COST_MODEL.md`
- `CHANGELOG.md` (new)

### Examples
- `examples/01-monte-carlo-portfolio.R`
- `examples/02-bootstrap-confidence-intervals.R`
- `examples/03-parallel-data-processing.R`
- `examples/04-grid-search-tuning.R`

### Tests
- `tests/testthat/test-ec2-integration.R` - Keep
- `tests/testthat/test-ec2-e2e.R` - Keep
- Remove any Fargate-specific tests

### Other
- `DESCRIPTION` - Bump version to 0.2.0
- `test-comparison.R` - Remove Fargate mode
- `benchmark-runner.R` - Remove Fargate mode

---

## Risk Mitigation

### Risk: Breaking existing users
**Mitigation**:
- Clear migration guide
- Deprecation warnings in v0.1.1
- Maintain v0.1.x branch for critical fixes

### Risk: Missing edge cases
**Mitigation**:
- Comprehensive test suite before release
- Beta testing with early adopters
- Gradual rollout

### Risk: Documentation gaps
**Mitigation**:
- Update all docs before code removal
- Add migration examples
- Update error messages to guide users

---

## Success Criteria

- [ ] All Fargate code removed
- [ ] All tests passing with EC2 only
- [ ] Documentation updated
- [ ] Examples working
- [ ] Migration guide complete
- [ ] Benchmarks show performance improvement
- [ ] Breaking changes clearly communicated

---

## Alternative: Deprecation Period

If we want to be more conservative:

**v0.1.1**: Add deprecation warnings
```r
if (launch_type == "FARGATE") {
  warning("Fargate support is deprecated and will be removed in v0.2.0. ",
          "Please migrate to EC2. See migration guide: ",
          "https://github.com/scttfrdmn/starburst/wiki/Fargate-to-EC2")
}
```

**v0.2.0**: Remove Fargate entirely (as planned above)

This gives users time to migrate, but adds ~1 month to timeline.

---

## Recommendation

**Proceed with removal** because:
1. Package is early (v0.1.0) - fewer existing users
2. EC2 is strictly better for this use case
3. Simplification enables faster feature development
4. Clear migration path exists

**Timeline**: ~7 days of focused work

**Release**: Aim for v0.2.0 within 2 weeks
