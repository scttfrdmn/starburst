# staRburst Profiling Plan

**Goal**: Understand why we're only getting 1.5x speedup instead of 5x+ with 50 workers vs 10 cores

**Current Results**:
- Expected: ~5x (50 workers / 10 cores)
- Actual: 1.5x
- Gap: 3.3x missing performance

---

## Hypothesis: Where is the 3.3x going?

### 1. Per-Core Performance Gap (Estimated: 2-3x impact)

**Observation**: AWS Fargate tasks appear much slower per-core than M4 Pro

**Potential Causes**:
- Default Fargate instances use Intel Skylake or older (~2.5 GHz)
- M4 Pro performance cores run at 3.5-4.0 GHz with better IPC
- Different CPU architectures (x86 vs ARM)
- No AVX-512 or other optimizations on Fargate

**How to measure**:
- ✅ Profiling script (running now) - compare compute time per iteration
- Run same task on different instance types (c7g, c7i, c6i)
- Check actual CPU model with `cat /proc/cpuinfo` in worker
- Benchmark single-threaded performance (LINPACK, etc.)

**Solutions to try**:
- Use c7i instances (latest Intel, up to 3.5 GHz all-core)
- Use c7g Graviton3 (better ARM performance than Fargate default)
- Use c6i instances (older but still better than default Fargate)
- Request more vCPUs per task (4-8 vCPUs may get better instances)

### 2. Startup Overhead (Estimated: 0.3-0.5x impact)

**Observation**: First result took 21.6 min vs 11.6 min expected (10 min overhead)

**Potential Causes**:
- Docker image pull time (~2-5 min for full image)
- Container startup time (~1-2 min)
- S3 data upload/download (~0.5-1 min)
- Task scheduling queue time (~1-2 min)

**How to measure**:
- Add timestamps at start of worker execution
- Measure time from task submission to first log
- Track Docker pull time separately
- Profile S3 transfer time with small test data

**Solutions to try**:
- Pre-pull images to workers (warm pool)
- Use smaller Docker images (multi-stage builds)
- Use public ECR (faster pull than private)
- Increase concurrent task launches
- Pre-warm ECS capacity

### 3. Straggler Effect (Estimated: 0.5-1x impact)

**Observation**: Last task took 46.5 min vs first 21.6 min (2.1x variance)

**Potential Causes**:
- Instance performance variation (some get slower CPUs)
- Resource contention (CPU, memory, network)
- Thermal throttling on some instances
- Unlucky scheduling (noisy neighbors)
- Network variability for S3 transfers

**How to measure**:
- ✅ Profiling script - measure task-to-task variance
- Log actual CPU model per worker
- Monitor CPU throttling during execution
- Track network latency/bandwidth per worker
- Histogram of completion times

**Solutions to try**:
- Speculative execution (launch 10% extra tasks, use first N)
- Task splitting (break large tasks into smaller chunks)
- Better load balancing (dynamic task assignment)
- Reserve instances (guaranteed performance)
- Use placement groups (collocate workers)

### 4. Coordination Overhead (Estimated: 0.1-0.2x impact)

**Observation**: Wall clock 46.5 min but longest task only ~40-42 min (estimated)

**Potential Causes**:
- ECS task scheduling delay
- S3 result collection time
- starburst_map polling overhead
- Network round-trips

**How to measure**:
- Log wall clock vs longest task time
- Profile S3 result download time
- Measure ECS API latency
- Track polling frequency/efficiency

**Solutions to try**:
- Batch S3 downloads
- Async result collection
- Reduce polling frequency
- Use EventBridge instead of polling

---

## Detailed Profiling Strategy

### Phase 1: Current Test (Running Now) ✅

**Script**: `/tmp/profiling-monte-carlo.R`

**Measures**:
- Local M4 Pro timing breakdown
- Cloud timing breakdown (10 workers)
- Per-task variance
- Computation vs overhead split

**Expected Output**:
- Exact per-core performance ratio (AWS / M4 Pro)
- Overhead per task
- Task variance statistics

### Phase 2: Instance Type Comparison

**Test**: Run same workload on different instance types

```r
test_instance_types <- function() {
  configs <- list(
    list(name = "default", cpu = 2, memory = 4),
    list(name = "c7g-2vcpu", cpu = 2, memory = 4),  # Graviton3
    list(name = "c7i-2vcpu", cpu = 2, memory = 4),  # Latest Intel
    list(name = "c6i-4vcpu", cpu = 4, memory = 8),  # More vCPUs
    list(name = "c7i-4vcpu", cpu = 4, memory = 8)   # Latest + more
  )

  for (config in configs) {
    timing <- starburst_map(
      1:5,
      benchmark_task,
      workers = 5,
      cpu = config$cpu,
      memory = config$memory
    )
    # Compare results
  }
}
```

**Expected**: Find instance type with 30-50% better per-core performance

### Phase 3: Overhead Profiling

**Add instrumentation to worker**:

```r
worker_function <- function(x) {
  timings <- list()

  # Log entry
  timings$worker_start <- Sys.time()
  cat(sprintf("WORKER_START: %s\n", timings$worker_start))

  # Check CPU info
  system("cat /proc/cpuinfo | grep 'model name' | head -1")

  # Data download timing
  timings$download_start <- Sys.time()
  # ... load data from S3 ...
  timings$download_end <- Sys.time()

  # Computation timing
  timings$compute_start <- Sys.time()
  result <- actual_computation(x)
  timings$compute_end <- Sys.time()

  # Upload timing
  timings$upload_start <- Sys.time()
  # ... upload result to S3 ...
  timings$upload_end <- Sys.time()

  timings$worker_end <- Sys.time()

  list(result = result, timings = timings)
}
```

**Expected**: Identify where time is being lost

### Phase 4: Straggler Analysis

**Track all task completion times**:

```r
# Modify starburst to return detailed timing per task
results <- starburst_map_with_timing(
  1:50,
  heavy_task,
  workers = 50
)

# Analyze distribution
completion_times <- sapply(results, function(r) r$completion_time)
hist(completion_times)
quantile(completion_times, c(0.5, 0.9, 0.95, 0.99, 1.0))
```

**Expected**: Understand if stragglers are:
- Random (just bad luck)
- Systematic (some workers always slow)
- Progressive (getting slower over time)

### Phase 5: Scale Testing

**Test if efficiency changes with scale**:

```r
scales <- list(
  list(tasks = 10, workers = 10),   # 1:1
  list(tasks = 50, workers = 25),   # 2:1
  list(tasks = 50, workers = 50),   # 1:1
  list(tasks = 100, workers = 50),  # 2:1
  list(tasks = 200, workers = 100)  # 2:1
)

for (scale in scales) {
  timing <- test_scale(scale$tasks, scale$workers)
  efficiency <- calculate_efficiency(timing)
  # Plot efficiency vs scale
}
```

**Expected**: Understand if we hit bottlenecks at scale

---

## Quick Wins to Test

### 1. Use c7i Instances (Latest Intel)

```r
# Change from default to c7i
starburst_map(
  data,
  fn,
  workers = 50,
  cpu = 2,
  memory = 4,
  instance_type = "c7i"  # Add this parameter
)
```

**Expected**: 30-50% faster per-core → 2-2.5x total speedup

### 2. Increase vCPUs per Task

```r
# Instead of 50 workers × 2 vCPUs
# Try 25 workers × 4 vCPUs
starburst_map(
  data,
  fn,
  workers = 25,
  cpu = 4,
  memory = 8
)
```

**Expected**: Better instance allocation, possibly faster CPUs

### 3. Pre-warm Workers

```r
# Keep a pool of warm workers
starburst_keep_warm(workers = 50, duration_minutes = 60)

# Then run
starburst_map(data, fn, workers = 50)  # Uses warm pool
```

**Expected**: Eliminate 10 min startup overhead

### 4. Speculative Execution

```r
# Launch 10% extra tasks
starburst_map(
  data,
  fn,
  workers = 50,
  oversubscribe = 1.1  # Launch 55 tasks for 50 items
)
# Use first 50 completions, cancel stragglers
```

**Expected**: Reduce impact of slow tasks

---

## Success Criteria

**Target**: Achieve 4-5x speedup (50 workers / 10 cores)

**Breakdown**:
- Baseline: 1.5x (current)
- Per-core optimization: +1.5x (better instances) → 2.25x total
- Startup optimization: +0.5x (warm pool) → 2.75x total
- Straggler mitigation: +0.75x (speculative exec) → 3.5x total
- Better task sizing: +0.5x (optimal batching) → 4x total

**Realistic target with optimizations**: **3-4x speedup**

---

## Next Steps

1. ✅ Wait for profiling results (running now)
2. Analyze per-core performance gap
3. Test c7i/c7g instance types
4. Implement warm worker pool
5. Add speculative execution for stragglers
6. Re-run ultimate showdown with optimizations

---

## Expected Findings

Based on symptoms:

1. **AWS Fargate default CPUs are 2-3x slower per-core than M4 Pro**
   - Likely: Older Intel Skylake vs M4 Pro's cutting-edge ARM
   - Fix: Use c7i or c7g instances

2. **10 min startup overhead is killing us**
   - First task: 21.6 min (10 min overhead + 11.6 min work)
   - Fix: Pre-warm workers

3. **Stragglers are significant** (2x variance)
   - Some tasks taking 40+ min vs 20 min
   - Fix: Speculative execution + better instance selection

4. **We can probably get to 3-4x with optimizations**
   - Not the 5x we'd expect from 5x more workers
   - But much better than current 1.5x
   - More honest assessment: "Cloud 3-4x faster with tuning"

---

## Documentation Needed

Once profiling complete:

1. **Instance type guide**
   - Performance comparison by instance type
   - Cost vs performance trade-offs
   - When to use each type

2. **Optimization checklist**
   - Quick wins (instance type, vCPUs)
   - Medium effort (warm pools)
   - Advanced (speculative execution)

3. **Performance expectations**
   - Realistic speedup ranges by workload
   - Efficiency by task duration
   - Cost per speedup gained

4. **Troubleshooting guide**
   - "My speedup is less than expected" → Check these
   - "Tasks are taking too long" → Profile these
   - "High variance in task times" → Try these

---

## Long-term Improvements

1. **Auto-optimization**
   - Automatically select best instance type
   - Auto-tune worker count
   - Dynamic task sizing

2. **Better monitoring**
   - Real-time performance dashboard
   - Per-worker CPU/memory graphs
   - Straggler alerts

3. **Advanced scheduling**
   - Speculative execution built-in
   - Auto-retry slow tasks on different instances
   - Smart work stealing

4. **Cost optimization**
   - Spot instances for non-critical work
   - Right-sizing recommendations
   - Reserved capacity for frequent users
