## Submission

This is a minor update from the current CRAN release (0.3.8) to 0.3.9.

### Notable changes in 0.3.9

* `starburst_map()` and `starburst_cluster()` now accept and forward the
  `launch_type` / `instance_type` / `use_spot` backend arguments (previously
  these functions had no backend selection).
* `starburst_setup()` provisions the default EC2 capacity provider so the
  default backend works out of the box (created at zero instances; no cost).
* Cost estimates now use live AWS pricing (Pricing API for On-Demand, EC2
  spot-price history for Spot), cached per session with a built-in static-rate
  fallback when offline; the `max_hourly_cost` guard and `cost_alert_threshold`
  are now enforced on every backend.
* Documentation consistency pass and several corrected examples.

See NEWS.md for the full list.

## Test environments

* local: macOS 26.5 (Tahoe), R 4.6.1
* GitHub Actions:
  - Ubuntu 22.04, R oldrel-1, release, devel
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
