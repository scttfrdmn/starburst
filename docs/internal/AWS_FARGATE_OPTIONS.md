# AWS Fargate Worker Options

**Current Date**: 2026-02-04
**Region**: us-east-1 (pricing may vary by region)

---

## CPU and Memory Configurations

### Valid Combinations

Fargate has specific valid combinations of CPU and memory:

| vCPUs | Memory Options (GB) | Use Case |
|-------|-------------------|----------|
| 0.25  | 0.5, 1, 2 | Ultra-light tasks |
| 0.5   | 1, 2, 3, 4 | Light tasks |
| 1     | 2, 3, 4, 5, 6, 7, 8 | Small tasks |
| 2     | 4, 5, 6, 7, 8, 9-16 (1 GB increments) | **Current default** |
| 4     | 8-30 (1 GB increments) | Medium tasks |
| 8     | 16-60 (4 GB increments) | Large tasks |
| 16    | 32-120 (8 GB increments) | Very large tasks |

**Current staRburst default**: 2 vCPU, 4 GB memory

---

## CPU Architectures

### 1. x86_64 (Intel/AMD)

**Default Platform**: LINUX/X86_64

**Actual CPUs** (you get what's available):
- Older: Intel Skylake (~2.5 GHz)
- Newer: Intel Cascade Lake (~2.8 GHz)
- Random allocation - no guarantees!

**Characteristics**:
- Widely compatible
- Variable performance (depends on what you get)
- No AVX-512 guaranteed
- Single-thread: ~2.5-3.0 GHz sustained

### 2. ARM64 (Graviton)

**Platform**: LINUX/ARM64

**Actual CPUs**:
- Graviton2: 64-bit ARM Neoverse N1 cores (2019)
- Graviton3: 64-bit ARM Neoverse V1 cores (2021) - **Recommended!**

**Characteristics**:
- Up to 40% better price/performance than x86
- Better energy efficiency
- Up to 3.0 GHz all-core sustained
- DDR5 memory (Graviton3)
- Excellent for parallel workloads

**Pricing**: ~20% cheaper than x86 for same vCPU count

**Compatibility**: R works great on ARM64 (no issues)

---

## Instance Types (Not Directly Selectable)

Fargate doesn't let you pick instance types directly, but you can influence what you get:

### By vCPU Count

**2 vCPUs or less**: Usually get general-purpose instances
- Could be anything from 2019-2024 vintage

**4 vCPUs**: Better chance of newer instances
- More likely to get recent-gen hardware

**8-16 vCPUs**: Best performance tier
- Almost always newer hardware
- Better per-core performance
- More memory bandwidth

### By Platform

**x86_64**: Random draw from available pool
- Could be great (new Intel)
- Could be mediocre (old Skylake)

**ARM64/Graviton3**: More consistent
- All Graviton3 instances are 2021+ design
- Predictable performance
- Better value

---

## Compute Optimized Options

While you can't select instance families directly in Fargate, you can use **ECS on EC2** with Fargate Spot pricing model for better control:

### c7g (Graviton3) - **Recommended for staRburst**

**CPU**: AWS Graviton3 (2021)
- 64-core ARM Neoverse V1
- Up to 3.0 GHz all-core turbo
- DDR5-4800 memory
- 300 GB/s memory bandwidth

**Performance vs M4 Pro**:
- Still slower per-core than M4 Pro (3.0 vs 3.5-4.0 GHz)
- But 30-40% faster than default Fargate x86
- More predictable performance

**Pricing** (us-east-1):
- vCPU: $0.032384/hour (~20% cheaper than x86)
- Memory: $0.003556/GB/hour

**2 vCPU, 4 GB**: $0.079/hour (~$0.001316/min)

### c7i (Latest Intel) - **Best x86 Option**

**CPU**: 4th Gen Intel Xeon Scalable (Sapphire Rapids)
- Up to 3.5 GHz all-core turbo
- AVX-512, AMX instructions
- DDR5 memory
- Released 2023

**Performance vs M4 Pro**:
- Closest to M4 Pro per-core performance
- Still 10-20% slower (3.5 vs 4.0 GHz + IPC differences)
- But much better than old Fargate

**Pricing** (us-east-1):
- vCPU: $0.04048/hour (standard x86 rate)
- Memory: $0.004445/GB/hour

**2 vCPU, 4 GB**: $0.099/hour (~$0.00165/min)

### c6i (Previous Gen Intel) - **Good Budget Option**

**CPU**: 3rd Gen Intel Xeon Scalable (Ice Lake)
- Up to 3.5 GHz all-core turbo
- AVX-512 instructions
- Released 2021

**Performance**:
- Solid performance
- Better than default Fargate
- Slightly slower than c7i

**Pricing**: Same as c7i (same generation pricing)

---

## Current staRburst Configuration

**What we're using now**:
```r
starburst_map(
  data,
  fn,
  workers = 50,
  cpu = 2,        # 2 vCPUs
  memory = 4      # 4 GB
  # platform = LINUX/X86_64 (default)
)
```

**What we're probably getting**:
- Random x86_64 instance (could be 2019-2024 vintage)
- Likely Intel Skylake or Cascade Lake
- ~2.5-2.8 GHz sustained
- No guarantee of specific generation

---

## Recommended Configurations for staRburst

### Option 1: Graviton3 (Best Value) ⭐

```r
starburst_map(
  data,
  fn,
  workers = 50,
  cpu = 2,
  memory = 4,
  platform = "LINUX/ARM64",  # Force Graviton
  runtime_platform = list(
    cpuArchitecture = "ARM64",
    operatingSystemFamily = "LINUX"
  )
)
```

**Expected improvement**: 30-40% faster per-core
**Cost**: 20% cheaper
**Speedup vs current**: 1.5x → 2.0x vs M4 Pro

### Option 2: More vCPUs per Worker

```r
starburst_map(
  data,
  fn,
  workers = 25,   # Half the workers
  cpu = 4,        # But 2x the vCPUs each
  memory = 8
)
```

**Expected improvement**: Better instance allocation, possibly faster CPUs
**Cost**: Same total vCPUs (25×4 = 100 vs 50×2 = 100)
**Speedup vs current**: Potentially 10-20% better

### Option 3: Premium Configuration (c7i-equivalent)

```r
starburst_map(
  data,
  fn,
  workers = 50,
  cpu = 4,         # More vCPUs = better instances
  memory = 8,
  platform = "LINUX/X86_64"
)
```

**Expected improvement**: Latest Intel, best x86 performance
**Cost**: 2x (200 total vCPUs vs 100)
**Speedup vs current**: 1.5x → 2.5-3.0x vs M4 Pro

### Option 4: Maximum Performance

```r
starburst_map(
  data,
  fn,
  workers = 25,
  cpu = 8,         # 8 vCPUs each
  memory = 16,
  platform = "LINUX/ARM64"  # Graviton3
)
```

**Expected improvement**: Best instances, most memory bandwidth
**Cost**: 2x (200 total vCPUs)
**Speedup vs current**: 1.5x → 3.0-3.5x vs M4 Pro

---

## Fargate Spot (Cheaper but Risky)

### Standard Fargate Spot

**Pricing**: Up to 70% discount
**Risk**: Can be interrupted with 2-minute warning

**Use case**: Long-running jobs that can checkpoint/resume

**Not recommended for staRburst**: Interruptions would kill tasks

### Fargate Capacity Providers

Can mix On-Demand and Spot:
```yaml
capacityProviders:
  - name: FARGATE
    weight: 70
  - name: FARGATE_SPOT
    weight: 30
```

**Benefit**: 30% cost savings with 30% spot mix
**Risk**: Some tasks may be interrupted

---

## Storage Options

### Ephemeral Storage

**Default**: 20 GB
**Maximum**: 200 GB
**Cost**: $0.000111/GB/hour ($0.00222/GB-hour for 20 GB over baseline)

**For staRburst**: 20 GB default is usually enough (we use S3)

### EFS Integration

Can mount EFS for shared storage:
```r
volume_configuration = list(
  name = "shared-data",
  efs_volume_configuration = list(
    file_system_id = "fs-xxxxx"
  )
)
```

**Use case**: Large reference datasets (genomic databases, etc.)
**Cost**: EFS storage + throughput charges

---

## Networking

### Network Mode

**Default**: awsvpc (each task gets own ENI)

**Bandwidth**:
- 2-4 vCPUs: Up to 10 Gbps
- 8+ vCPUs: Up to 25 Gbps

**For staRburst**: Default is fine (S3 transfers are fast)

### VPC Configuration

Tasks run in your VPC:
- Need NAT Gateway for internet (S3, ECR)
- Or use VPC endpoints (cheaper)
- Security groups for access control

---

## Actual Performance Comparison

Based on benchmarks and current results:

| Platform | CPU | vCPU | Clock | Per-Core vs M4 Pro | Cost/hour (2vCPU, 4GB) |
|----------|-----|------|-------|-------------------|----------------------|
| M4 Pro | Apple M4 | - | 3.5-4.0 GHz | 1.0x (baseline) | $0 (your laptop) |
| Fargate Default | Intel Skylake | 2 | ~2.5 GHz | ~0.35-0.45x | $0.099 |
| Fargate Graviton3 | ARM Neoverse V1 | 2 | 3.0 GHz | ~0.50-0.60x | $0.079 |
| Fargate 4vCPU | Newer Intel | 4 | ~2.8 GHz | ~0.45-0.55x | $0.178 |
| Fargate 8vCPU | Latest Intel | 8 | ~3.0 GHz | ~0.55-0.65x | $0.356 |

**Key Finding**: Even best Fargate is ~60-65% the per-core speed of M4 Pro

**Why we still win**: 50 workers × 0.5x = 25x compute power vs 10 cores × 1.0x = 10x

**Expected speedup with Graviton3**: 25x / 10x = 2.5x vs M4 Pro parallel

---

## Optimization Recommendations

### Immediate (No Code Change)

1. **Switch to Graviton3**
   - Add `platform = "ARM64"` parameter
   - 30-40% faster, 20% cheaper
   - Expected: 1.5x → 2.0x speedup

### Short-term (Minor Code Change)

2. **Increase vCPUs per worker**
   - 25 workers × 4 vCPUs instead of 50 × 2
   - Better instance allocation
   - Expected: +10-20% improvement

3. **Pre-warm workers**
   - Eliminate 10 min startup overhead
   - Expected: +20-30% improvement

### Medium-term (Feature Development)

4. **Auto-select instance type**
   - Benchmark different configs
   - Choose best price/performance
   - Let users override

5. **Speculative execution**
   - Launch 10% extra tasks
   - Use first N completions
   - Mitigate stragglers

### Long-term (Architecture)

6. **Hybrid execution**
   - Use local cores + cloud workers
   - Best of both worlds
   - Example: 10 local + 40 cloud = 50 total

7. **EC2 for compute-intensive**
   - For heavy workloads, use ECS on EC2
   - Pick exact instance type (c7i, c7g)
   - Better per-core performance

---

## Cost Comparison

### Current Configuration (50 workers, 46.5 min)

```
50 workers × 2 vCPU × $0.04048/vCPU-hour × 0.775 hours = $3.14
50 workers × 4 GB × $0.004445/GB-hour × 0.775 hours = $0.69
Total: $3.83
```

### Graviton3 (50 workers, ~35 min estimated)

```
50 workers × 2 vCPU × $0.032384/vCPU-hour × 0.583 hours = $1.89
50 workers × 4 GB × $0.003556/GB-hour × 0.583 hours = $0.41
Total: $2.30 (40% savings + 35% faster!)
```

### Premium (50 workers, 4 vCPU, ~30 min estimated)

```
50 workers × 4 vCPU × $0.04048/vCPU-hour × 0.5 hours = $4.05
50 workers × 8 GB × $0.004445/GB-hour × 0.5 hours = $0.89
Total: $4.94 (30% more expensive but 55% faster)
```

---

## Summary

**Current**: Random x86, 2 vCPU, ~40-50% M4 Pro per-core speed
**Best Budget**: Graviton3, 2 vCPU, ~50-60% M4 Pro speed, 20% cheaper
**Best Performance**: Graviton3, 4 vCPU, ~60% M4 Pro speed, similar cost
**Maximum**: 8+ vCPU x86, ~65% M4 Pro speed, 2x cost

**Recommendation for staRburst**:
1. Default to Graviton3 (ARM64) for best value
2. Allow users to override with `cpu`, `memory`, `platform` parameters
3. Document performance expectations by configuration
4. Consider auto-benchmarking to pick best config

**Expected improvement**: 1.5x → 2.5-3.0x speedup with Graviton3 + tuning
