## Resubmission (2nd)

This resubmission addresses all NOTEs from previous CRAN auto-checks.

### Previous rejection (2026-02-18):
> Package has a VignetteBuilder field but no prebuilt vignette index.

**Root cause:** The `.Rbuildignore` rule `^.*\.rds$` was inadvertently
excluding `build/vignette.rds` (the prebuilt vignette index) from the
package tarball. Fixed by removing that rule and committing
`build/vignette.rds` directly.

**win-builder (R-devel, 2026-02-27):** 0 errors | 0 warnings | 1 NOTE
(only "New submission" — VignetteBuilder NOTE is resolved).

## Test environments

* local: macOS 14.2 (Tahoe), R 4.5.2
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

The package provides seamless AWS cloud bursting for parallel R workloads
on AWS (EC2 and Fargate backends).

Key points for reviewers:
- All tests requiring AWS credentials are gated with `skip_if_offline()`
  and will not run on CRAN's test servers
- Package includes 12 vignettes with real-world examples in `inst/doc/`
- Default backend is EC2 with spot instances for cost optimization
- Fully documented with 29+ exported functions
