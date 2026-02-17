## Test environments

* local: macOS 14.2 (Tahoe), R 4.5.2
* GitHub Actions:
  - Ubuntu 22.04, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel, R-release

## R CMD check results

0 errors ✓ | 0 warnings ✓ | 0 notes ✓

## Downstream dependencies

There are currently no downstream dependencies for this package.

## CRAN submission notes

This is a new submission of the staRburst package. The package provides seamless AWS cloud bursting capabilities for parallel R workloads.

All tests that require AWS credentials are properly gated with `skip_if_offline()` and will not run on CRAN's test servers.
