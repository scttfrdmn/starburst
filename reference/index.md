# Package index

## Start here

Set up once, then run your first job.

- [`starburst-package`](https://starburst.ing/reference/starburst-package.md)
  : starburst: Seamless AWS Cloud Bursting for Parallel R Workloads
- [`starburst_setup()`](https://starburst.ing/reference/starburst_setup.md)
  : Setup staRburst
- [`starburst_is_configured()`](https://starburst.ing/reference/starburst_is_configured.md)
  : Check if staRburst is configured

## Core execution

Run work across AWS workers.

- [`starburst_map()`](https://starburst.ing/reference/starburst_map.md)
  : Map a Function Over Data on AWS Workers
- [`starburst_cluster()`](https://starburst.ing/reference/starburst_cluster.md)
  : Create a Starburst Cluster

## future / furrr integration

Use staRburst as a future backend for existing future/furrr code.

- [`plan(`*`<starburst>`*`)`](https://starburst.ing/reference/plan.starburst.md)
  : staRburst Future Backend
- [`starburst()`](https://starburst.ing/reference/starburst.md) :
  Starburst strategy marker

## Detached sessions

Long-running jobs that survive your R session closing.

- [`starburst_session()`](https://starburst.ing/reference/starburst_session.md)
  : Create a Detached Starburst Session
- [`starburst_session_attach()`](https://starburst.ing/reference/starburst_session_attach.md)
  : Reattach to Existing Session
- [`starburst_list_sessions()`](https://starburst.ing/reference/starburst_list_sessions.md)
  : List All Sessions

## Configuration

Account and backend defaults.

- [`starburst_config()`](https://starburst.ing/reference/starburst_config.md)
  : Configure staRburst options
- [`starburst_status()`](https://starburst.ing/reference/starburst_status.md)
  : Show staRburst status

## Monitoring, logs & cost

- [`starburst_logs()`](https://starburst.ing/reference/starburst_logs.md)
  : View worker logs
- [`starburst_estimate()`](https://starburst.ing/reference/starburst_estimate.md)
  : Estimate Cloud Performance and Cost
- [`starburst_quota_status()`](https://starburst.ing/reference/starburst_quota_status.md)
  : Show quota status
- [`starburst_check_quota_request()`](https://starburst.ing/reference/starburst_check_quota_request.md)
  : Monitor quota increase request
- [`starburst_request_quota_increase()`](https://starburst.ing/reference/starburst_request_quota_increase.md)
  : Request quota increase (user-facing)

## Infrastructure setup

One-time provisioning and maintenance.

- [`starburst_setup_ec2()`](https://starburst.ing/reference/starburst_setup_ec2.md)
  : Setup EC2 capacity providers for staRburst
- [`starburst_rebuild_environment()`](https://starburst.ing/reference/starburst_rebuild_environment.md)
  : Rebuild environment image
- [`starburst_cleanup_ecr()`](https://starburst.ing/reference/starburst_cleanup_ecr.md)
  : Clean up staRburst ECR images

## Developer & internal

Extension points and future-backend internals; not needed for normal
use.

- [`StarburstBackend()`](https://starburst.ing/reference/StarburstBackend.md)
  : Starburst Future Backend
- [`StarburstFuture()`](https://starburst.ing/reference/StarburstFuture.md)
  : StarburstFuture Constructor
- [`future(`*`<starburst>`*`)`](https://starburst.ing/reference/future.starburst.md)
  : Create a Future using Starburst Backend
- [`launchFuture(`*`<StarburstBackend>`*`)`](https://starburst.ing/reference/launchFuture.StarburstBackend.md)
  : Launch a future on the Starburst backend
- [`listFutures(`*`<StarburstBackend>`*`)`](https://starburst.ing/reference/listFutures.StarburstBackend.md)
  : List futures for StarburstBackend
- [`nbrOfWorkers(`*`<StarburstBackend>`*`)`](https://starburst.ing/reference/nbrOfWorkers.StarburstBackend.md)
  : Number of workers for StarburstBackend
- [`resolved(`*`<StarburstFuture>`*`)`](https://starburst.ing/reference/resolved.StarburstFuture.md)
  : Check if StarburstFuture is Resolved
- [`result(`*`<StarburstFuture>`*`)`](https://starburst.ing/reference/result.StarburstFuture.md)
  : Get Result from StarburstFuture
- [`run(`*`<StarburstFuture>`*`)`](https://starburst.ing/reference/run.StarburstFuture.md)
  : Run a StarburstFuture
- [`print(`*`<StarburstSessionStatus>`*`)`](https://starburst.ing/reference/print.StarburstSessionStatus.md)
  : Print method for session status
- [`session-api`](https://starburst.ing/reference/session-api.md) :
  Detached Session API
