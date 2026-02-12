# staRburst AWS Cost Model

## TL;DR

**Idle cost with auto-cleanup enabled: $0**
**Idle cost without auto-cleanup: ~$0.50/month**

## What Costs Money

### 1. EC2 Instances (MAIN COST - only when running)

| Component | On-Demand | Spot | Billing |
|-----------|-----------|------|---------|
| c6a.large (AMD 3rd Gen) | $0.0765/hr | ~$0.0229/hr | Per-second |
| c8a.large (AMD 8th Gen - BEST) | $0.0918/hr | ~$0.0275/hr | Per-second |
| c7g.xlarge (Graviton3) | $0.1450/hr | ~$0.0435/hr | Per-second |

**Auto-scaling**: Scales to 0 when idle = $0 cost
**Example**: 10 workers @ 4 vCPU = ~20 c6a.large instances = $1.53/hr (on-demand)

### 2. ECR Docker Images (storage cost)

| Item | Size | Cost | Auto-Cleanup |
|------|------|------|--------------|
| Base image | ~2GB | $0.20/month | Yes (if TTL set) |
| Environment image | ~3GB | $0.30/month | Yes (if TTL set) |
| **Total** | ~5GB | **$0.50/month** | **Yes** |

**ECR Auto-Cleanup** (recommended):
```r
starburst_setup(ecr_image_ttl_days = 30)
```
- AWS automatically deletes images after 30 days
- Works even if you never run staRburst again
- Rebuild on next use adds 3-5 min delay
- **Idle cost: $0**

### 3. Free AWS Resources

These cost $0 at all times:
- ✅ ECS Cluster
- ✅ ECS Capacity Providers
- ✅ Auto-Scaling Groups
- ✅ Launch Templates
- ✅ IAM Roles/Policies
- ✅ Security Groups
- ✅ S3 bucket (negligible: ~$0.023/GB/month for results)

## Cost Control Strategies

### Strategy 1: Zero Idle Cost (Recommended for Infrequent Use)

```r
starburst_setup(ecr_image_ttl_days = 7)
```

- **Idle cost**: $0
- **Tradeoff**: 3-5 min rebuild delay if >7 days since last use
- **Best for**: Monthly/quarterly workloads, learning, experiments

### Strategy 2: Minimal Idle Cost (Recommended for Regular Use)

```r
starburst_setup(ecr_image_ttl_days = 30)
```

- **Idle cost**: ~$0.50/month (if you abandon project before 30 days)
- **Benefit**: No rebuild delay for regular users
- **Best for**: Weekly/daily workloads, production use

### Strategy 3: Always Ready (Default)

```r
starburst_setup()  # No TTL
```

- **Idle cost**: ~$0.50/month (forever)
- **Benefit**: Zero startup delay, always cached
- **Best for**: Active development, frequent use

## Real-World Cost Examples

### Example 1: Weekly Data Analysis (100 workers, 1 hour/week)

**Setup**:
```r
starburst_setup(ecr_image_ttl_days = 30)
plan(starburst, workers = 100, instance_type = "c6a.large", use_spot = TRUE)
```

**Monthly cost**:
- Compute: 4 hours @ $4.58/hr (spot) = **$18.32**
- ECR: $0 (still within 30-day TTL)
- **Total: ~$18/month**

### Example 2: Daily ML Training (50 workers, 2 hours/day)

**Setup**:
```r
starburst_setup(ecr_image_ttl_days = 30)
plan(starburst, workers = 50, instance_type = "c8a.large", use_spot = TRUE)
```

**Monthly cost**:
- Compute: 60 hours @ $2.75/hr (spot) = **$165**
- ECR: $0 (daily use within TTL)
- **Total: ~$165/month**

### Example 3: One-Time Analysis (Abandoned After Use)

**Setup**:
```r
starburst_setup(ecr_image_ttl_days = 7)
plan(starburst, workers = 20, instance_type = "c6a.large")
```

**Cost after forgetting about it**:
- Month 1: $0.31 (run once) + $0 (TTL cleanup) = **$0.31**
- Month 2+: **$0** (images auto-deleted)
- No surprise bills ✅

### Example 4: No TTL Set (Worst Case)

**Setup**:
```r
starburst_setup()  # No TTL
plan(starburst, workers = 10)
```

**Cost after abandoning**:
- Run once: $0.31
- Every month after: **$0.50** (ECR storage)
- After 1 year of no use: **$6** in surprise costs

## How to Check Current Costs

```r
# Check configuration
config <- starburst:::get_starburst_config()
config$ecr_image_ttl_days  # NULL = no auto-cleanup

# Check image age
starburst_cleanup_ecr()  # Shows all images and ages

# Force cleanup now
starburst_cleanup_ecr(force = TRUE)  # Delete all images immediately
```

## Cost Comparison: EC2 vs Fargate

| Metric | EC2 (staRburst) | Fargate |
|--------|-----------------|---------|
| vCPU cost | $0.0191/hr (c6a spot) | $0.04048/hr |
| Cold start | <30s (warm pool) | 10+ min |
| Idle cost (instances) | $0 (scales to 0) | $0 |
| Idle cost (images) | $0 (with TTL) | $0 |
| Instance choice | ✅ Force Graviton/AMD | ❌ AWS chooses |

**Savings**: EC2 is ~50% cheaper per vCPU than Fargate

## Best Practices

1. **Always set TTL for new projects**:
   ```r
   starburst_setup(ecr_image_ttl_days = 30)
   ```

2. **Use spot instances** (70% savings):
   ```r
   plan(starburst, use_spot = TRUE)
   ```

3. **Set warm pool timeout** (default: 1 hour):
   ```r
   plan(starburst, warm_pool_timeout = 600)  # 10 min
   ```

4. **Manual cleanup when done**:
   ```r
   starburst_cleanup_ecr(force = TRUE)
   ```

5. **Monitor with AWS Cost Explorer**:
   - Tag: `ManagedBy: starburst`
   - Filter by `starburst-*` resources

## Preventing Surprise Bills

The ECR auto-cleanup feature is **specifically designed to prevent surprise bills** from forgotten resources. This addresses a major blocker for cloud adoption:

**Before auto-cleanup**:
- Run job once → forget about it → $6/year in surprise ECR costs
- Fear of cloud: "What if I forget to clean up?"

**After auto-cleanup**:
- Run job once → AWS auto-deletes after TTL → $0 cost
- Peace of mind: "Just works, no surprise bills"

This is why we recommend **always setting ecr_image_ttl_days** unless you know you'll use staRburst regularly.

## Summary

| Use Case | Recommended TTL | Idle Cost | Notes |
|----------|-----------------|-----------|-------|
| Learning / Experiments | 7 days | $0 | Best for one-time use |
| Monthly workloads | 30 days | ~$0 | Almost zero idle cost |
| Weekly workloads | 30 days | $0.50/month worst case | Likely $0 in practice |
| Daily workloads | NULL | $0.50/month | Always cached |
| Production | 60 days | $0.50/month | Balance convenience and cost |

**The key insight**: ECR cleanup is the ONLY ongoing cost when not running jobs, and it's automatically solved with TTL. Everything else scales to $0.
