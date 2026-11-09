## Submission

This is a patch update from the current CRAN release (0.3.11, accepted
2026-11-06) to 0.3.12. I'm sorry for the quick succession: 0.3.11 restored
the package's main backend, and testing it end to end on AWS uncovered
further bugs that affect users' cloud resources, including one where shutting
down a cluster stopped other users' running jobs.

### Bug fixes in 0.3.12

* Shutting down a cluster stopped every staRburst task in the shared ECS
  cluster, including other users' jobs; it now stops only its own tasks.
* Futures waited forever when a remote worker died without returning a
  result; they now fail with the reason reported by ECS.
* Task and result objects were never deleted from the user's S3 bucket.
* The `warm_pool_timeout` setting had no effect; it is now implemented, with
  a lower default (600 s).
* Building the remote worker image reinstalled every package already present
  in its base image (up to ~30 minutes); it now installs only what differs.
* `future (>= 1.40.0)` is now required: the backend API the package uses
  (`launchFuture()`, `stopWorkers()`) does not exist in older versions.

Offline regression tests cover all of these. No exported function was
removed; a `stopWorkers()` method was added. See NEWS.md.

## Test environments

* local: Docker rocker/r-ver:4.6.1 (Ubuntu 24.04, aarch64), R 4.6.1
* GitHub Actions:
  - Ubuntu latest, R oldrel-1, release, devel
  - Windows latest, R release, devel
  - macOS latest, R release

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Days since last update: (a few days)

  This is the quick follow-up explained above.

All tests requiring AWS credentials are gated (skipped on CRAN); `\donttest`
examples guard on `starburst_is_configured()` and make no network calls when
credentials are absent.

## Downstream dependencies

There are currently no downstream dependencies for this package.
