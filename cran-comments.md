## Resubmission (5th)

This resubmission fixes the invalid file URI flagged by CRAN's pretest in v0.3.8.

### Changes made in this resubmission:

1. **Fixed invalid LICENSE URI in README.md**: Replaced relative file URI
   `[LICENSE](LICENSE)` with full GitHub URL
   `[LICENSE](https://github.com/scttfrdmn/starburst/blob/main/LICENSE)`.
   CRAN's pretest flagged: "Found the following (possibly) invalid file URI:
   URI: LICENSE From: README.md"

No other changes were made. Version remains 0.3.8.

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
