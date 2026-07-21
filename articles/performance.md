# Performance Guide: When to Use Cloud vs Local

## The Honest Truth

Cloud is not magic. It has overhead, costs money, and AWS CPUs are
slower per-core than a modern laptop like an M4 Pro. But with the right
instance types and spot pricing, cloud can be both faster and cheaper
than you expect.

**Cloud wins when:**

- Total workload \> 2–4 hours sequential
- You run the same analysis multiple times (parameter sweeps, recurring
  jobs)
- You need results faster than local parallel can deliver
- Your laptop needs to stay usable
- Budget allows \$1–5 per job (often less with spot instances)

**Local wins when:**

- Workload \< 1 hour
- One-time quick analysis
- You have a powerful multi-core machine (16+ cores)
- Data is too sensitive for cloud
- Zero budget

------------------------------------------------------------------------

## Real Performance Data

These are **real measured runs** from `bench/benchmark.R` (see
`bench/README.md`) on live AWS — full cold starts, nothing excluded.
They’re chosen to show *both* sides, so you can calibrate when bursting
is worth it. Same setup for both: staRburst 0.3.9, us-east-1, EC2
`c7i.xlarge` Spot, cold start, sequential baseline on an Apple M4 Pro
(Mac16,11; 12 cores = 8 performance + 4 efficiency, 48 GB, macOS 26.5.2,
R 4.6.1), 2026-07-21.

### ✅ When it pays off — heavy per-task work

30 tasks, each ~10 s of dense linear algebra (repeated SVD):

| Phase                                    | Time                  |
|------------------------------------------|-----------------------|
| Local (sequential, 1 pass over 30 tasks) | 319.3 s (5.3 min)     |
| Cloud: startup (provision + image pull)  | 87.5 s                |
| Cloud: compute + collect (30 workers)    | 38.4 s                |
| **Cloud total (cold)**                   | **125.8 s (2.1 min)** |
| Est. cost                                | \$0.06                |

**~2.5× faster even counting the full ~90 s cold startup** — because the
30 tasks finish in parallel in ~38 s instead of ~5 min sequentially. Run
this as a warm pool or a parameter sweep and the startup amortizes away,
pushing the speedup higher.

### ❌ When it doesn’t — light per-task work

20 tasks, each a fraction of a second (small terrain-stat grids):

| Phase                    | Time        |
|--------------------------|-------------|
| Local (sequential)       | 0.1 s       |
| Cloud: startup           | 74.7 s      |
| Cloud: compute + collect | 27.9 s      |
| **Cloud total (cold)**   | **102.6 s** |
| Est. cost                | \$0.03      |

**~1000× *slower* than local.** The work is trivial, so the fixed
startup is pure overhead with nothing to amortize it against. Running
this locally is the right call.

### The lesson

Same tool, same 20–30 workers, opposite verdicts. The only thing that
changed is **how much work each task does**. If your tasks are
seconds-to-minutes each and you have many of them, staRburst wins; if
they’re sub-second, stay local. The rest of this guide makes that
boundary precise.

------------------------------------------------------------------------

## Per-Task Overhead

Once workers are running, each task incurs a small fixed overhead from
S3 data transfer:

| Task Duration | Overhead % | Efficiency |
|---------------|------------|------------|
| 1 second      | 200–300%   | Negative   |
| 10 seconds    | 20–30%     | Moderate   |
| 30 seconds    | 7–10%      | Good       |
| 60 seconds    | 3–5%       | Excellent  |
| 5 minutes     | \<1%       | Optimal    |

**Sweet spot**: tasks that run for 2–10 minutes each. For faster tasks,
batch them.

------------------------------------------------------------------------

## Batching

The most important optimization. Instead of sending 10,000 tiny tasks,
group them:

``` r

# Bad: 10,000 tasks of 0.1s each — overhead dominates
starburst_map(1:10000, quick_fn, workers = 100)
```

``` r

# Good: 100 tasks of 100s each — overhead is negligible
batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))
starburst_map(batches, function(batch) lapply(batch, quick_fn), workers = 100)
```

**Batch size formula:**

``` r

# Profile your function first
per_item_time <- 0.5   # seconds, from local profiling
target_task_duration <- 60  # aim for 60s minimum per task

batch_size <- ceiling(target_task_duration / per_item_time)
# Result: 120 items per batch
```

------------------------------------------------------------------------

## Choosing Instance Types

| Instance | Architecture  | Price/Perf | Best For                 |
|----------|---------------|------------|--------------------------|
| **c8a**  | AMD 8th gen   | ★★★★★      | Default — best overall   |
| **c8g**  | Graviton4 ARM | ★★★★       | Best ARM64 option        |
| **c7a**  | AMD 7th gen   | ★★★★       | Proven, stable           |
| **c8i**  | Intel 8th gen | ★★★        | High single-thread needs |

``` r

# Recommended: c8a with spot instances
plan(starburst,
  workers     = 50,
  instance_type = "c8a.xlarge",  # AMD 8th gen — best price/performance
  use_spot    = TRUE             # 70% cheaper than on-demand
)
```

**Spot vs on-demand (50 workers, us-east-1):**

    c8a on-demand:  $7.20/hr
    c8a spot:       $2.16/hr   ← 70% savings, low interruption risk

------------------------------------------------------------------------

## The Startup Cost Problem

Workers need ~75–90 s to start cold (pool warmup + image pull +
environment sync). This cost is **fixed** — it doesn’t scale with job
size. The key is to amortize it. The numbers below extrapolate from the
measured “heavy” run above (5.3 min local vs ~90 s startup + ~38 s
compute on 30 workers).

### Run once (cold) — modest win

    Local (sequential):        5.3 min, $0
    Cloud 30 workers (cold):   2.1 min ($0.06)   [87s startup + 38s compute]
      → ~2.5x faster, laptop freed — worth it, but startup is most of the cloud time

### Run 10 times (parameter sweep) — much better

    Local (sequential):        53 min (10 × 5.3), laptop tied up
    Cloud (pool stays warm):   ~8 min (90s startup ONCE + 10 × ~38s compute)
      → Startup paid once, then each run is ~38s. Big win, laptop stays usable.

### Daily recurring job — excellent

    Warm pool started once in the morning; every run pays ~0 startup.
      → Per-run cost is just compute+collect (~38s here); startup overhead ≈ 0%.
      → Best case for staRburst — see the "keep warm pool" pattern below.

------------------------------------------------------------------------

## Decision Framework

The real question isn’t total job length — it’s **per-task work vs. the
~90 s cold startup**, and **how many times you’ll run it**. The measured
examples above bracket it: the heavy workload won at ~5 min of
sequential work; the trivial one lost badly. As a rule of thumb for a
**single cold run**:

    Per-task work is sub-second:   Stay local (startup is pure overhead)
    Tasks are seconds–minutes,
      and there are many:          Cloud wins — this is the sweet spot
    Total sequential work < ~2 min: Local usually wins on a cold start

Running it **more than once** changes everything — a warm pool pays the
~90 s startup once, so even modest jobs win on the 2nd+ run (see below).

**How many times will you run it?**

    Once:          Startup is ~20% of job time
    2–5 times:     Startup amortizes to ~5–10%
    10+ times:     Startup < 2%
    Daily:         Keep warm pool, effectively zero

**What’s your local hardware?**

    4–6 cores:         Cloud dominates
    8–10 cores (M4):   Cloud wins but it's closer
    16+ cores:         Cloud might not win on speed
    HPC cluster:       Use your cluster

------------------------------------------------------------------------

## Common Patterns

### Pattern: One-shot analysis — use local

``` r

library(parallel)
cl <- makeCluster(detectCores() - 1)
results <- parLapply(cl, data, your_function)
stopCluster(cl)
```

### Pattern: Parameter sweep — use cloud

``` r

# Pay startup cost once, run many combinations
for (alpha in seq(0.1, 1.0, 0.1)) {
  for (beta in seq(0.1, 1.0, 0.1)) {
    results <- starburst_map(
      data,
      function(x) model(x, alpha = alpha, beta = beta),
      workers = 50
    )
  }
}
```

### Pattern: Daily production job — keep warm pool

``` r

# Start warm pool once in the morning
plan(starburst, workers = 50, warm_pool_timeout = 28800)  # 8 hours

# All runs during the day start in < 30s
results_am <- starburst_map(morning_data, process)
results_pm <- starburst_map(afternoon_data, process)
# Pool shuts down automatically after 8 hours of inactivity
```

### Pattern: Hybrid — develop local, scale on cloud

``` r

# Iterate quickly on a small sample locally
results_test <- lapply(data[1:100], your_function)

# When logic is right, scale to full dataset on cloud
results_full <- starburst_map(data, your_function, workers = 100)
```

------------------------------------------------------------------------

## Cost Estimation

**Quick formula (EC2 spot, us-east-1):**

    Cost ≈ workers × hours × $0.044/worker/hour

| Job size                 | Workers | Wall time | Spot cost |
|--------------------------|---------|-----------|-----------|
| Small (1 hr sequential)  | 10      | ~6 min    | ~\$0.04   |
| Medium (5 hr sequential) | 25      | ~12 min   | ~\$0.22   |
| Large (10 hr sequential) | 50      | ~25 min   | ~\$0.92   |

Use
[`starburst_estimate()`](https://starburst.ing/reference/starburst_estimate.md)
for a precise estimate before running.

------------------------------------------------------------------------

## Common Pitfalls

**Too many small tasks:**

``` r

# Bad: each task is 0.1s — overhead is 20-30x the work
starburst_map(1:10000, function(x) sqrt(x), workers = 100)

# Good: batch into groups of 100
batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))
starburst_map(batches, function(b) sapply(b, sqrt), workers = 100)
```

**More workers than tasks:**

``` r

# Bad: 40 workers sit idle
starburst_map(1:10, fn, workers = 50)

# Good: match workers to workload
starburst_map(1:100, fn, workers = 25)  # 4 tasks per worker
```

**Sending large data to every worker:**

``` r

# Bad: huge_matrix serialized and sent to each of 50 workers
huge_matrix <- matrix(rnorm(1e8), ncol = 1000)
starburst_map(1:50, function(i) process(huge_matrix, i), workers = 50)

# Good: generate data inside the worker
starburst_map(1:50, function(i) {
  data <- generate_chunk(i)  # create data on the worker
  process(data)
}, workers = 50)
```

------------------------------------------------------------------------

## Use Case Quick Reference

| Use Case          | Task Duration | Batch Size      | Workers | Expected Speedup |
|-------------------|---------------|-----------------|---------|------------------|
| Fast calculations | 0.001s        | 1000+ per task  | 20–50   | 3–8x             |
| API calls         | 0.5–2s        | 20–100 per task | 20–50   | 8–15x            |
| Data processing   | 10–60s        | 5–20 per task   | 20–50   | 12–20x           |
| Report generation | 60–300s       | 1–5 per task    | 20–50   | 15–25x           |
| Model training    | 2–10 min      | 1–2 per task    | 20–50   | 18–30x           |

------------------------------------------------------------------------

## AWS Authentication

staRburst uses the [paws](https://github.com/paws-r/paws) AWS SDK, which
supports the full AWS credential chain:

- **Environment variables**: `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
- **Named profiles**: set `AWS_PROFILE=myprofile` to select a profile
  from `~/.aws/credentials`
- **AWS SSO / `aws login`**: supported via named profiles configured
  with SSO in `~/.aws/config` (requires AWS CLI v2, `aws login`
  available since November 2025)
- **IAM instance roles**: automatic when running on EC2 or ECS

``` bash
# Standard profile
export AWS_PROFILE=my-aws-account
Rscript -e "library(starburst); starburst_setup_ec2()"

# SSO profile (AWS CLI v2)
aws login --profile my-sso-profile
export AWS_PROFILE=my-sso-profile
Rscript -e "library(starburst); starburst_setup_ec2()"
```

No explicit configuration is required in staRburst — it defers entirely
to paws credential discovery.
