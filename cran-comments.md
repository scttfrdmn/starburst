## Submission

This is a patch update from the current CRAN release (0.3.9, accepted
2026-07-22) to 0.3.10, fixing a significant silent-failure bug.

### Bug fix in 0.3.10

* The Docker template shipped in `inst/templates/Dockerfile.base` (used at
  runtime to build worker base images) did not install `cmake`, which
  RcppParallel >= 6.2.0 now requires. As a result `qs2` silently failed to
  install in locally built images and remote workers could not deserialize
  tasks. The template now installs `cmake` and fails the build if any required
  package is missing.
* A test that round-trips a `qs2` blob now skips when `qs2` is not loadable.

No R code or exported API changes. See NEWS.md.

## Test environments

* local: Docker rocker/r-ver:4.6.1 (Ubuntu 24.04, aarch64), R 4.6.1
* GitHub Actions:
  - Ubuntu latest, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel

## R CMD check results

0 errors | 0 warnings | 0 notes

All tests requiring AWS credentials are gated (skipped on CRAN); `\donttest`
examples guard on `starburst_is_configured()` and make no network calls when
credentials are absent.

## Downstream dependencies

There are currently no downstream dependencies for this package.
