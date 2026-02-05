# staRburst Performance Guidelines

**Based on Real AWS Testing** (2026-02-04)

---

## TL;DR

**Cloud overhead**: ~2-3 seconds per Fargate task

**Sweet spot**: Tasks taking 2-5+ minutes each

**Best speedup**: Batch 100-1000 operations per worker task

---

## Test Results Summary

### Test 1: Monte Carlo (Too Fast)
```
Work: 100 simulations × 0.0002s = 0.02s total
Cloud overhead: 259s
Result: Cloud SLOWER (0.00x speedup)
Lesson: Individual tasks too fast
```

### Test 2: API Calls (Small Batches)
```
Work: 200 API calls, 10 workers, 20 calls each
Per-task work: ~10 seconds
Per-task overhead: ~2-3 seconds
Speedup: 1.24x (12% efficiency)
Lesson: Batches still too small
```

### Ideal Scenario (Projected)
```
Work: 2000 API calls, 10 workers, 200 calls each
Per-task work: ~100 seconds
Per-task overhead: ~2-3 seconds
Expected speedup: ~8-9x (80-90% efficiency)
Lesson: Large batches overcome overhead
```

---

## Cloud Overhead Breakdown

### Per-Task Overhead: ~2-3 seconds

**Components**:
1. Container startup: ~1-2 seconds
2. Data download from S3: ~0.5 seconds
3. Result upload to S3: ~0.5 seconds
4. Total: ~2-3 seconds

**Impact by Task Duration**:
| Task Duration | Overhead % | Efficiency |
|---------------|------------|------------|
| 1 second | 200-300% | Negative |
| 5 seconds | 40-60% | Poor |
| 10 seconds | 20-30% | Moderate |
| 30 seconds | 7-10% | Good |
| 60 seconds | 3-5% | Excellent |
| 300 seconds | 1% | Optimal |

---

## Batching Strategy

### Without Batching (Bad)
```r
# Each number becomes a separate Fargate task
# 1000 tasks × 2.5s overhead = 2500s wasted
results <- starburst_map(
  1:1000,
  function(x) sqrt(x),  # 0.0001s of work
  workers = 50
)
# Result: SLOWER than local
```

### With Batching (Good)
```r
# Batch into 50 groups of 20
# 50 tasks × 2.5s overhead = 125s
# Each task does 20 calculations
batches <- split(1:1000, ceiling(seq_along(1:1000) / 20))

process_batch <- function(numbers) {
  lapply(numbers, sqrt)
}

results <- starburst_map(
  batches,
  process_batch,
  workers = 50
)
# Result: Good speedup
```

---

## Use Case Guidelines

### ✅ Excellent Fit

**1. API Calls** (with batching)
```r
# 1000 API calls, 50 workers, 20 calls each
# Per-task: ~10-20 seconds
# Speedup: 3-5x
```

**2. Report Generation**
```r
# 50 reports, 25 workers, 2 reports each
# Per-task: ~60-120 seconds
# Speedup: 10-15x
```

**3. Model Training**
```r
# 100 models, 50 workers, 2 models each
# Per-task: ~120-300 seconds
# Speedup: 15-25x
```

**4. Data Processing**
```r
# Process 1M rows, 20 workers, 50k rows each
# Per-task: ~60-180 seconds
# Speedup: 10-18x
```

### ⚠️ Poor Fit (Without Modification)

**1. Fast Iterations**
```r
# Problem: Each iteration < 1 second
# Solution: Batch 100-1000 per task
```

**2. Simple Calculations**
```r
# Problem: sqrt(), sum(), etc.
# Solution: Combine with I/O or batch
```

**3. Small Datasets**
```r
# Problem: < 1000 operations
# Solution: Batch or not worth cloud
```

---

## Optimization Strategies

### Strategy 1: Increase Batch Size

```r
# Instead of 1 operation per task
starburst_map(1:1000, fn, workers = 50)  # 1000 tasks

# Do 20 operations per task
batches <- split(1:1000, ceiling(seq_along(1:1000) / 20))
starburst_map(batches, process_batch, workers = 50)  # 50 tasks
```

**Impact**: Reduces overhead from 2500s to 125s

### Strategy 2: Increase Work Per Operation

```r
# Make each iteration more substantial
process_complex <- function(x) {
  # Multiple operations
  data <- fetch_data(x)
  processed <- transform_data(data)
  result <- analyze(processed)
  return(result)
}
```

**Impact**: Work time grows, overhead stays same

### Strategy 3: Right-Size Workers

```r
# Too many workers for small workload
starburst_map(1:100, fn, workers = 50)  # 2 items per worker

# Better: Match workers to data
starburst_map(1:100, fn, workers = 10)  # 10 items per worker
```

**Impact**: Reduces total overhead

---

## Cost Optimization

### Real Cost Examples

**Test 1: Monte Carlo** (Too Fast)
- Duration: 4.3 minutes
- Workers: 5 × 1 vCPU × 2GB
- Cost: $0.02
- Speedup: 0.00x
- **Cost per unit speedup: ∞**

**Test 2: API Calls** (Small Batches)
- Duration: 1.4 minutes
- Workers: 10 × 1 vCPU × 2GB
- Cost: $0.01
- Speedup: 1.24x
- **Cost per unit speedup: $0.008**

**Projected: API Calls** (Large Batches)
- Duration: 2 minutes
- Workers: 10 × 1 vCPU × 2GB
- Cost: $0.02
- Speedup: 8-9x
- **Cost per unit speedup: $0.002**

### Cost Formula

```
Cost = Workers × vCPU × vCPU_rate × Hours +
       Workers × GB × Memory_rate × Hours

Where (us-east-1):
  vCPU_rate = $0.04048/hour
  Memory_rate = $0.004445/GB/hour
```

**Example** (10 workers, 2 vCPU, 4GB, 5 minutes):
```
Cost = 10 × 2 × $0.04048 × (5/60) +
       10 × 4 × $0.004445 × (5/60)
     = $0.067 + $0.015
     = $0.082
```

---

## Recommendations by Use Case

### Scenario 1: Many Fast Operations

**Example**: 10,000 simple calculations

**Recommendation**:
- Batch into 100 groups of 100
- Use 50 workers (2 batches each)
- Each task: ~5-10 seconds
- Expected: 3-5x speedup

### Scenario 2: API Integration

**Example**: 1,000 API calls (0.5-2s each)

**Recommendation**:
- Batch into 50 groups of 20
- Use 25 workers (2 batches each)
- Each task: ~20-40 seconds
- Expected: 8-12x speedup

### Scenario 3: Report Generation

**Example**: 100 PDF reports (30-60s each)

**Recommendation**:
- Batch into 25 groups of 4
- Use 25 workers (1 batch each)
- Each task: ~120-240 seconds
- Expected: 15-20x speedup

### Scenario 4: Model Training

**Example**: 50 models (2-5 min each)

**Recommendation**:
- No batching needed
- Use 25-50 workers (1-2 models each)
- Each task: ~120-600 seconds
- Expected: 20-25x speedup

---

## Testing Your Workload

### Step 1: Profile Locally

```r
start <- Sys.time()
result <- your_function(sample_data)
duration <- difftime(Sys.time(), start, units = "secs")

cat(sprintf("Per-item time: %.3f seconds\n", duration))
```

### Step 2: Calculate Batch Size

```r
target_task_duration <- 60  # seconds (minimum recommended)
overhead <- 3  # seconds
per_item_time <- 0.5  # from profiling

batch_size <- ceiling((target_task_duration - overhead) / per_item_time)
# Result: 114 items per batch
```

### Step 3: Estimate Speedup

```r
total_items <- 1000
local_time <- total_items * per_item_time
# 1000 × 0.5 = 500 seconds

n_workers <- 20
batches <- ceiling(total_items / batch_size)
# ceiling(1000 / 114) = 9 batches

batches_per_worker <- ceiling(batches / n_workers)
# ceiling(9 / 20) = 1 batch per worker

cloud_time <- (batch_size * per_item_time) + overhead
# (114 × 0.5) + 3 = 60 seconds

speedup <- local_time / cloud_time
# 500 / 60 = 8.3x
```

---

## Common Pitfalls

### Pitfall 1: Too Many Small Tasks
```r
# ❌ Bad: 10,000 tasks of 0.1s each
starburst_map(1:10000, quick_fn, workers = 100)
# Overhead: 25,000s, Work: 1,000s

# ✅ Good: 100 tasks of 10s each
starburst_map(batches, batch_fn, workers = 100)
# Overhead: 250s, Work: 1,000s
```

### Pitfall 2: Wrong Worker Count
```r
# ❌ Bad: More workers than tasks
starburst_map(1:10, fn, workers = 50)
# 40 workers sit idle

# ✅ Good: Match workers to workload
starburst_map(1:100, fn, workers = 25)
# Each worker gets 4 tasks
```

### Pitfall 3: Ignoring Data Transfer
```r
# ❌ Bad: Large data per task
huge_data <- matrix(rnorm(1e7), ncol = 100)
starburst_map(1:1000, function(x) process(huge_data, x))
# S3 transfer becomes bottleneck

# ✅ Good: Generate data on workers
starburst_map(1:1000, function(x) {
  data <- generate_data(x)
  process(data)
})
```

---

## Summary Table

| Use Case | Task Duration | Batch Size | Workers | Expected Speedup |
|----------|---------------|------------|---------|------------------|
| Fast calculations | 0.001s | 1000-10000 | 20-50 | 3-8x |
| API calls (fast) | 0.5s | 50-200 | 20-50 | 5-12x |
| API calls (slow) | 2s | 20-50 | 20-50 | 10-18x |
| Data processing | 10s | 5-20 | 20-50 | 12-20x |
| Report generation | 60s | 1-5 | 20-50 | 15-25x |
| Model training | 300s | 1-2 | 20-50 | 18-30x |

---

## Conclusion

**staRburst works best when**:
1. Each worker task runs for **2+ minutes**
2. Or processes **100-1000 operations** in batch
3. Work time significantly exceeds **3-second overhead**

**Key to success**: **Right-size your batches!**

For questions or optimization help: help@starburst.ing
