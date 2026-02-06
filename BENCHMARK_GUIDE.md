# staRburst Benchmark Guide

This guide helps you benchmark staRburst performance comparing:
1. **Local sequential** - Single-core baseline
2. **Local parallel on orion.local** - Multi-core server
3. **staRburst EC2 x86_64** - Cloud with Intel/AMD instances
4. **staRburst EC2 ARM64** - Cloud with Graviton instances
5. **staRburst EC2 Spot** - 70% cost savings

## Quick Start

### Option 1: Automated (Recommended)

Run all benchmarks automatically:

```bash
cd /Users/scttfrdmn/src/starburst
./run-benchmarks.sh
```

This will:
- Run local sequential baseline
- Run parallel benchmark on orion.local (if accessible)
- Run EC2 benchmarks with different configurations
- Generate comparison report

### Option 2: Manual (Step-by-Step)

Run each benchmark individually:

```bash
# 1. Local sequential (baseline)
Rscript benchmark-runner.R local-seq

# 2. Local parallel on orion.local
ssh orion.local
cd /path/to/starburst
Rscript benchmark-runner.R local-par
exit

# 3. EC2 x86_64 (from your Mac)
Rscript benchmark-runner.R ec2

# 4. EC2 ARM64 Graviton (from your Mac)
Rscript benchmark-runner.R ec2-arm64

# 5. EC2 Spot instances (from your Mac)
Rscript benchmark-runner.R ec2-spot

# 6. Compare all results
Rscript benchmark-runner.R compare
```

## Quick Validation Test

Before running full benchmarks, verify everything works:

```bash
# Test locally (fast - 10 tasks)
Rscript test-quick.R local

# Test EC2 (fast - 10 tasks, 5 workers)
Rscript test-quick.R ec2

# Test EC2 ARM64
Rscript test-quick.R ec2-arm64
```

## What Gets Benchmarked

The benchmark runs 1,000 Monte Carlo portfolio simulations. Each simulation:
- Generates 252 days of stock returns
- Calculates portfolio metrics (return, drawdown, Sharpe ratio)
- Takes ~0.02 seconds per simulation

**Total computational time:**
- Sequential: ~20 seconds
- Parallel (8 cores): ~3 seconds
- Cloud (25 workers): ~1-2 seconds

## Expected Results

| Mode | Workers | Time | Cost | Speedup |
|------|---------|------|------|---------|
| Local Sequential | 1 | ~20s | $0 | 1x |
| Local Parallel (orion) | 8 | ~3s | $0 | ~7x |
| EC2 x86 (c6a.large) | 25 | ~1.5s | ~$0.01 | ~13x |
| EC2 ARM64 (c7g.xlarge) | 25 | ~1.5s | ~$0.008 | ~13x |
| EC2 Spot | 25 | ~1.5s | ~$0.003 | ~13x |

## Benchmark Files

Results are saved as `.rds` files:
- `benchmark-results-local-sequential-TIMESTAMP.rds`
- `benchmark-results-local-parallel-TIMESTAMP.rds`
- `benchmark-results-starburst-ec2-TIMESTAMP.rds`

Each file contains:
- System information
- Configuration (workers, instance type, etc.)
- Performance metrics (elapsed time, throughput)
- Results summary statistics
- Raw simulation results

## Comparing Results

View comparison table:

```bash
Rscript benchmark-runner.R compare
```

This shows:
- Execution time for each mode
- Throughput (simulations/second)
- Speedup vs baseline
- Cost estimates for cloud runs

## Running Existing Examples

Test with the full example suite:

```bash
# Local execution
Rscript examples/01-monte-carlo-portfolio.R

# EC2 execution
USE_STARBURST=TRUE STARBURST_WORKERS=50 Rscript examples/01-monte-carlo-portfolio.R
```

Available examples:
- `01-monte-carlo-portfolio.R` - Portfolio risk simulation
- `02-bootstrap-confidence-intervals.R` - A/B test analysis
- `03-parallel-data-processing.R` - Batch data processing
- `04-grid-search-tuning.R` - ML hyperparameter tuning

## Troubleshooting

### "Cannot connect to orion.local"

If you can't SSH to orion.local:
- Verify SSH is configured: `ssh orion.local 'echo OK'`
- Or run benchmarks locally instead

### "starburst not configured"

Run setup first:
```r
Sys.setenv(AWS_PROFILE = "aws")
devtools::load_all()
starburst_setup()
```

### EC2 pool not starting

Check:
- AWS credentials: `aws sts get-caller-identity`
- EC2 setup completed: `starburst_setup_ec2()`
- Pool status: View Auto Scaling Group in AWS Console

### Multi-platform image not found

Rebuild base image:
```r
build_base_image(
  region = "us-east-1",
  r_version = "4.5.2",
  force_rebuild = TRUE
)
```

## Cost Breakdown

For 1,000 simulations with 25 EC2 workers:

**c6a.large (x86_64)**
- Instance price: $0.0765/hour
- Instances needed: ~3 (25 workers, 2 vCPU each)
- Runtime: ~2 minutes
- Cost: $0.0765 * 3 * (2/60) = **$0.0077**

**c7g.xlarge (ARM64 Graviton)**
- Instance price: $0.0578/hour (24% cheaper!)
- Instances needed: ~2 (25 workers, 4 vCPU each)
- Runtime: ~2 minutes
- Cost: $0.0578 * 2 * (2/60) = **$0.0039**

**c6a.large SPOT**
- Instance price: ~$0.023/hour (70% discount)
- Cost: $0.023 * 3 * (2/60) = **$0.0023**

## Next Steps

After benchmarking:

1. **Choose optimal configuration**
   - ARM64 for best price/performance
   - Spot for lowest cost
   - x86 for compatibility

2. **Update your workflows**
   ```r
   plan(starburst,
        workers = 50,
        launch_type = "EC2",
        instance_type = "c7g.xlarge",  # Graviton
        use_spot = TRUE)
   ```

3. **Monitor costs**
   - Check AWS Cost Explorer
   - Set billing alerts
   - Use ECR TTL to prevent idle costs

## Questions?

- Check `AWS_COST_MODEL.md` for detailed cost analysis
- View `SESSION_SUMMARY.md` for implementation details
- Run `starburst_status()` to check cluster state
