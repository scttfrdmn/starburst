# staRburst Architecture

## Overview

staRburst runs parallel R workloads on AWS with no infrastructure to
manage. It registers a `future` backend named **`starburst`**, so
`plan(starburst, workers = N)` turns ordinary `future`/`furrr` code into
cloud execution, and it exposes a direct
[`starburst_map()`](https://starburst.ing/reference/starburst_map.md)
API for the common map-over-inputs case.

Workers run on **Amazon ECS**. The default backend launches **EC2
instances** (`c7g.xlarge`, Spot enabled) for speed and cost; a
serverless **Fargate** backend is available as an alternative. In both
cases the compute plane is decoupled from the data plane: tasks,
results, and session state all flow through **S3**, and worker R
environments are reproduced from your `renv.lock` as a Docker image
cached in **ECR**.

## Design Principles

1.  **EC2-first for speed and cost.** The default backend is EC2 with
    Spot (`use_spot = TRUE`) — no cold start, ~70% cheaper than
    On-Demand, any instance type, and warm pools that amortize startup
    across runs. Fargate is offered for workloads that specifically want
    serverless task execution.
2.  **Sensible defaults over configuration.**
    [`starburst_setup()`](https://starburst.ing/reference/starburst_setup.md)
    provisions everything the default backend needs; a first job is
    `plan(starburst, workers = N)` with no further tuning.
3.  **S3 is the message bus.** The client and workers never talk
    directly. S3 is the RPC channel: the client writes tasks, workers
    write results, and both read state. This is what makes
    disconnect/reattach and detached sessions possible.
4.  **Reproducible environments.** Worker packages come from your
    `renv.lock`, baked into a Docker image and cached in ECR — the same
    versions locally and remotely.
5.  **Transparent (estimated) cost.** Every run reports an estimate
    derived from measured worker runtime and live AWS pricing, with hard
    and soft ceilings.

## System Architecture

The mental model (from the *Getting Started* guide):

            Local R session
                  |
                  |  (1) serialize your function + inputs + detected globals (qs2)
                  |      AWS credentials are read HERE, from your local environment
                  v
       S3 bucket  +  staRburst control plane (ECS/ECR)
                  |
                  |  (2) launch workers: EC2 (default, Spot) or Fargate
                  |      each worker's R packages come from your renv.lock, baked
                  |      into a Docker image cached in ECR
                  v
       Remote R workers  (one task per input element)
                  |
                  |  (3) each worker pulls a task from S3, runs it, writes the
                  |      result + logs back to S3
                  v
       Local R session  <-- results collected in order (starburst_map / cluster)
            or
       Detached-session store in S3  <-- collected later via starburst_session_attach()

Key properties of this picture:

- **Credentials** are used only on your machine (to call AWS) and by the
  workers’ IAM role. No keys go into your code or into S3.
- **Uploaded per task**: your function, its inputs, and auto-detected
  globals — not your whole workspace. Large data should be put in S3
  yourself and read on the worker.
- **After a disconnect**, workers keep running against S3 until a
  timeout; nothing is silently lost.

## Components

### Client library (local)

Responsibilities: environment snapshot (renv), task serialization,
worker launch, result collection, cost estimation, and (for Fargate)
quota-aware wave planning.

Key modules:

    R/
    ├── plan-starburst.R          # plan.starburst(): backend construction, defaults, guards
    ├── StarburstBackend-class.R  # `starburst` strategy marker + FutureBackend integration
    ├── future-starburst.R        # future.starburst() / StarburstFuture, run/resolved/result
    ├── setup.R                   # starburst_setup(), starburst_setup_ec2(), starburst_config()
    ├── ec2-pool.R                # capacity providers, ASGs, warm pools (EC2 backend)
    ├── session-api.R             # detached sessions (submit / status / collect / cleanup)
    ├── session-state.R           # S3-backed manifest + task status (atomic, ETag-guarded)
    ├── cost.R                    # estimate_cost() + live AWS pricing with static fallback
    ├── images.R                  # renv -> multi-arch base + worker image, cached in ECR
    └── aws-retry.R / aws-clients.R

### Backend selection (EC2 default, Fargate optional)

[`plan.starburst()`](https://starburst.ing/reference/plan.starburst.md)
and
[`starburst_session()`](https://starburst.ing/reference/starburst_session.md)
default to `launch_type = "EC2"`, `instance_type = "c7g.xlarge"`,
`use_spot = TRUE`. Both backends submit ECS `run_task` calls; they
differ only in how capacity is provided:

|  | EC2 (default) | Fargate (optional) |
|----|----|----|
| Selector | `launch_type = "EC2"` | `launch_type = "FARGATE"` |
| Capacity | Auto Scaling Group + ECS capacity provider | Managed by AWS |
| Setup needed | Capacity provider (created by [`starburst_setup()`](https://starburst.ing/reference/starburst_setup.md)) | None |
| Startup | Warm pool (~75–90 s cold, then reused) | Per-task cold start |
| Cost lever | Spot (default), any instance type | Fargate vCPU pricing |
| Scale limit | EC2 On-Demand / Spot instance limits | Fargate vCPU quota (wave-based) |

``` r

# Default: EC2 + Spot, c7g.xlarge
plan(starburst, workers = 50)

# Serverless alternative
plan(starburst, workers = 50, launch_type = "FARGATE")
```

Worker count is capped at 500 (`validate_workers()`); higher requires an
AWS quota increase.

### One-time setup

[`starburst_setup()`](https://starburst.ing/reference/starburst_setup.md)
is a single call that provisions everything the default backend needs:

- an S3 bucket (encrypted, 7-day lifecycle) for the task/result/session
  data plane;
- an ECR repository for worker images;
- an ECS cluster and VPC resources shared by both backends;
- the **default EC2 capacity provider** — a Launch Template, an Auto
  Scaling Group at `DesiredCapacity = 0`, and an ECS capacity provider
  for `c7g.xlarge`. Creating it at zero instances means no compute cost
  from setup, but the default EC2 backend works on the first job. Skip
  with `setup_ec2 = FALSE` if you only use Fargate.
- a Fargate vCPU quota check (with an optional increase request);
- the initial worker image build (skippable with `build_image = FALSE`;
  built lazily on first launch otherwise).

Capacity providers for **non-default instance types are provisioned
lazily**: the first time a job requests, say, `c8a.xlarge`,
[`start_warm_pool()`](https://starburst.ing/reference/start_warm_pool.md)
finds no ASG and calls
[`setup_ec2_capacity_provider()`](https://starburst.ing/reference/setup_ec2_capacity_provider.md)
once (idempotent). You can also pre-provision several types with
`starburst_setup_ec2(instance_types = c(...))`.

``` r

starburst_setup()                          # default: EC2 capacity + image build
starburst_setup(build_image = FALSE)       # provision infra only (CI / connectivity)
starburst_setup(setup_ec2 = FALSE)         # Fargate-only
```

### Environment reproduction (renv + Docker + ECR)

Workers must run the same package versions as your local session:

    1. renv.lock (exact package versions), discovered by walking up to the project root
            |
            v
    2. Docker build
       ├─ multi-arch base image (linux/amd64 + linux/arm64), public
       │  (public.ecr.aws/.../base:r<version>) or privately built
       ├─ renv::restore(renv.lock)
       └─ + worker entrypoint (inst/templates/worker.R)
            |
            v
    3. ECR cache, tagged by a hash of the environment (compute_env_hash)
       ├─ hash unchanged  -> reuse cached image  (seconds)
       └─ packages changed -> rebuild + push      (first run: ~5-10 min)

The multi-arch base lets the same logical image run on Graviton (ARM64,
e.g. `c7g`) and x86 (`c7i`/`c8a`) workers. Separately, the EC2 *hosts*
boot from the region’s ECS-optimized AMI (ARM64 or x86 to match the
instance).

## Execution Model

### Data flow

1.  Locally, staRburst captures `{expr, globals, packages}`
    (auto-detecting globals via
    [`future::getGlobalsAndPackages()`](https://future.futureverse.org/reference/getGlobalsAndPackages.html)),
    serializes it with **qs2**, and uploads it to
    `s3://<bucket>/tasks/<task_id>.qs`.
2.  It launches workers (EC2 warm pool or Fargate tasks) via ECS
    `run_task`, passing `TASK_ID`, `S3_BUCKET`, and region as container
    environment variables.
3.  Each worker pulls its task from S3, restores globals/packages,
    evaluates the expression, and writes the result (or a structured
    error) to `s3://<bucket>/results/<task_id>.qs`.
4.  The client polls `results/` (via `resolved()` / `result()`) and
    returns values in submission order — or, for detached sessions,
    leaves them in S3 for later.

### One task per element (no auto-chunking)

staRburst creates **one task per element of `.x`** — there is no
automatic batching. Each task is a separate client-side S3 submit and
collect, so thousands of tiny tasks is an anti-pattern: the client
serializes submissions (~1–2/sec) while workers sit idle, and cost
scales with idle worker time. The four levers that decide whether a
workload fits (see the *Workload Shapes* guide) are:

- **Task length** — sub-second tasks should stay local;
  seconds-to-minutes each is the sweet spot.
- **Task count** — batch fine-grained work into dozens-to-hundreds of
  tasks, each doing real work. A 10k-point sweep is ~65× faster and ~27×
  cheaper batched vs. one task per point.
- **Fan-out width** — more workers cut wall-clock only up to the number
  of tasks; beyond `workers == tasks` you pay for idle machines.
- **Cost vs. time** — adding workers (up to \#tasks) buys wall-clock at
  ~constant total cost; Spot (default) and warm pools cut cost for
  anything run more than once.

``` r

# DON'T: 10,000 tasks — 10,000 serial S3 submits
results <- starburst_map(1:10000, evaluate_point, workers = 50)

# DO: batch into ~100 tasks, same 10,000 evaluations
batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))
results <- starburst_map(batches, function(ids) lapply(ids, evaluate_point),
                         workers = 50)
results <- unlist(results, recursive = FALSE)
```

### Wave-based execution (Fargate quota handling)

The Fargate vCPU quota is a hard account limit. When a Fargate job
requests more vCPUs than the quota allows,
[`plan.starburst()`](https://starburst.ing/reference/plan.starburst.md)
computes `workers_per_wave` and `num_waves` and runs the tasks in
sequential waves, optionally offering a quota-increase request. This
logic is **Fargate-specific**: the EC2 backend is bounded by ordinary
EC2 On-Demand / Spot instance limits, not this quota, and does not use
waves.

## Cost Model

Reported cost is an **estimate, not an AWS bill.**
[`estimate_cost()`](https://starburst.ing/reference/estimate_cost.md)
produces a normalized `hourly_rate` (total \$/hour for the whole job)
that works for both backends:

- **EC2**: `instances_needed × per-instance hourly rate`, where the rate
  is looked up live — On-Demand from the AWS Pricing API, Spot from EC2
  spot-price history — cached per session, and falling back to a
  built-in static price table when offline or for unknown types.
- **Fargate**: `workers × (cpu × vCPU-hour + memory × GB-hour)` at
  published Fargate rates.

Final per-run cost is measured worker runtime (from ECS task start/stop
times) times that rate — close to reality, but not the figure from AWS
billing / Cost Explorer.

Guardrails via
[`starburst_config()`](https://starburst.ing/reference/starburst_config.md)
(both are hourly *rates*, USD/hour):

``` r

starburst_config(
  max_hourly_cost = 10,        # hard stop: jobs estimated over $10/hr won't start
  cost_alert_threshold = 5     # soft warning at $5/hr
)
```

`max_hourly_cost` raises an error before launch; `cost_alert_threshold`
only warns. Both fire on the EC2 default because the estimate is
normalized across backends.

## Detached Sessions

[`starburst_session()`](https://starburst.ing/reference/starburst_session.md)
decouples a job’s lifetime from your R session. It launches workers
immediately (EC2 + Spot by default) and returns a handle whose
`$session_id` you can persist:

``` r

session <- starburst_session(workers = 50)              # EC2 + Spot by default
ids <- lapply(inputs, function(x)                       # fan out: one task per input
  session$submit(quote(f(x)), globals = list(x = x)))
sid <- session$session_id                               # save this, then close R

# Later, from a fresh R session:
session <- starburst_session_attach(sid)
session$status()                                         # pending/running/completed/failed
results <- session$collect(wait = TRUE)                  # keyed by task id, in order
session$cleanup()                                        # preserves S3 unless force = TRUE
```

Mechanics:

- **State lives in S3.** A manifest at `sessions/<id>/manifest.qs` and
  per-task status at `sessions/<id>/tasks/<task_id>/status.qs`; results
  share the `results/` prefix. Manifest updates are atomic (ETag-guarded
  conditional writes with backoff) so concurrent workers and clients
  don’t clobber each other.
- **Failures are visible, not fatal.** A failed task is recorded and
  does not abort the others; `collect()` returns it as a structured
  failure entry
  (`list(error = TRUE, message = ..., value = NULL, task_id = ...)`)
  alongside the successful results. `collect(wait = TRUE)` blocks until
  every *user* task is terminal (long-lived bootstrap/worker tasks are
  excluded so it doesn’t hang).
- **Cleanup preserves data by default.** `cleanup()` stops workers and
  marks the session terminated but leaves S3 objects intact so you can
  still inspect/collect; pass `force = TRUE` to also delete the
  session’s S3 task/result objects. Sessions do not auto-clean on
  garbage collection — they self-terminate at `absolute_timeout`.

Ephemeral runs
([`starburst_map()`](https://starburst.ing/reference/starburst_map.md),
`plan(starburst)`) instead auto-clean on completion:
[`cleanup_cluster()`](https://starburst.ing/reference/cleanup_cluster.md)
stops tasks, reports runtime/cost, removes the job’s S3 objects (unless
`auto_cleanup_s3 = FALSE`), and for EC2 keeps the warm pool alive until
`warm_pool_timeout` so repeated jobs skip the cold start.

## Security

- **Credentials** are read only from your local environment; workers use
  IAM roles.
- **IAM roles** (created at setup): `starburstECSExecutionRole` (pull
  images / logs), `starburstECSTaskRole` (task S3 access), and for the
  EC2 backend `starburstECSInstanceRole` / `starburstECSInstanceProfile`
  on the hosts.
- **S3 bucket** is private, encrypted at rest (SSE-S3), with a 7-day
  lifecycle on transfer objects.
- **Command execution** on the client is routed through a
  [`safe_system()`](https://starburst.ing/reference/safe_system.md)
  wrapper (whitelisted commands, no shell expansion) to prevent
  injection.

## Extension Points

- **New backend:** implement the `future` backend contract
  (`StarburstBackend` factory + `future`/`run`/`resolved`/`result`
  methods) — the S3 task/result protocol is backend-agnostic.
- **New instance families:** add fallback prices to
  [`.static_ec2_prices()`](https://starburst.ing/reference/dot-static_ec2_prices.md)
  in `R/cost.R`; capacity providers are created lazily, so no other
  wiring is needed.
- **Serialization / data plane:** tasks and results are qs2 blobs under
  `tasks/` and `results/`; alternative formats plug in at
  [`run.StarburstFuture()`](https://starburst.ing/reference/run.StarburstFuture.md)
  /
  [`result.StarburstFuture()`](https://starburst.ing/reference/result.StarburstFuture.md).

## Future Directions

EC2 and Spot are **shipped**, not roadmap. What remains ahead:

- **GPU support** — GPU instance families and NVIDIA-enabled worker
  images for accelerated workloads.
- **Enhanced error recovery** — automatic task-level retry/resubmission
  on Spot interruption.
- **Interactive progress monitoring** and **multi-region** execution.

## References

- [`future` framework](https://future.futureverse.org/)
- [renv](https://rstudio.github.io/renv/)
- [AWS Fargate pricing](https://aws.amazon.com/fargate/pricing/) · [EC2
  Spot](https://aws.amazon.com/ec2/spot/) · [AWS Service
  Quotas](https://docs.aws.amazon.com/servicequotas/)
- Guides:
  [`vignette("getting-started")`](https://starburst.ing/articles/getting-started.md),
  [`vignette("workload-shapes")`](https://starburst.ing/articles/workload-shapes.md),
  [`vignette("detached-sessions")`](https://starburst.ing/articles/detached-sessions.md),
  [`vignette("performance")`](https://starburst.ing/articles/performance.md)
