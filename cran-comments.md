## Resubmission (4th)

This resubmission bumps the version to 0.3.8 and fixes critical bugs
discovered during integration testing after the v0.3.7 submission.

### Changes made in v0.3.8:

1. **Worker script fix**: Removed invalid `timeout` parameter from
   `paws.storage::s3()` config in `inst/templates/worker.R`. The paws
   package only accepts `connect_timeout`, not `timeout`. Workers were
   crashing immediately on startup with "invalid name: timeout".

2. **Environment hash consistency**: Added `compute_env_hash()` helper to
   ensure consistent hash computation across `ensure_environment()` and
   `starburst_rebuild_environment()`. This prevents unnecessary Docker
   image rebuilds and ensures workers always use the correct image.

3. **Lockfile discovery fix**: `ensure_environment()` now correctly finds
   the package root `renv.lock` when called from test subdirectories.
   testthat sets CWD to `tests/testthat/` which caused `renv::paths$lockfile()`
   to find a test-specific lockfile instead of the package root one.

4. **Version bump**: v0.3.7 → v0.3.8 to trigger environment image rebuild
   with the fixed worker script.

## Test environments

* local: macOS 26.3 (Tahoe), R 4.5.2
* GitHub Actions:
  - Ubuntu 22.04, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel (r89498)

## R CMD check results

0 errors ✓ | 0 warnings ✓ | 1 NOTE

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Scott Friedman <help@starburst.ing>'

New submission
```

This NOTE is expected and unavoidable for any new CRAN submission.

## Downstream dependencies

There are currently no downstream dependencies for this package.

## CRAN submission notes

The package provides seamless 'Amazon Web Services' ('AWS') cloud bursting
for parallel R workloads on 'EC2' and 'Fargate'.

Key points for reviewers:
- All tests requiring AWS credentials are gated with `skip_if_offline()`
  and will not run on CRAN's test servers
- Package includes 12 vignettes with real-world examples in `inst/doc/`
- Default backend is 'EC2' with spot instances for cost optimization
- Fully documented with 29+ exported functions
