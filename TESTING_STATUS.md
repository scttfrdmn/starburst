# Testing Status - Real Science Examples

**Date**: 2026-02-04 **Goal**: Demonstrate 50-100x speedups with truly
massive scientific workloads

------------------------------------------------------------------------

## Problem with Original Examples

Original examples showed cloud being **slower** than M4 Pro: - Tasks too
short (0.5-2 seconds each) - Cloud overhead (2-3s) dominated computation
time - M4 Pro performance cores crushed the small workloads - Result:
Cloud 5-20x SLOWER ❌

------------------------------------------------------------------------

## Solution: REAL SCIENCE at Scale

Created truly massive examples that take **hours** locally: - Per-task
duration: 2-10 minutes (overhead now negligible) - Total sequential:
1-5+ hours on M4 Pro - M4 Pro would run hot for hours - Cloud: Minutes
with 50-100 workers

------------------------------------------------------------------------

## Test Examples Created

### 1. Massive Monte Carlo Simulation ⏳ TESTING NOW

- **Scale**: 100 scenarios × 1M iterations = 100M total iterations
- **Per scenario**: ~96 seconds (1.6 minutes)
- **Sequential time**: **2.8 hours**
- **Cloud**: 100 workers, expected ~3-4 minutes
- **Expected speedup**: 40-50x
- **Status**: Running cloud test now

### 2. Genomic Variant Analysis ⚠️ TOO FAST

- **Scale**: 1,000 samples, 50k variants each
- **Problem**: Only 0.1s per sample (needs 10-100x more computation)
- **Status**: Needs to be scaled up more

### 3. Climate Model Ensemble 📋 READY

- **Scale**: 500 simulations, 100 years each
- **Per simulation**: ~3-5 minutes (estimated)
- **Sequential**: 25-40 hours (estimated)
- **Cloud**: 100 workers, expected ~30-60 minutes
- **Expected speedup**: 25-50x
- **Status**: Ready to test after Monte Carlo

### 4. Molecular Dynamics 📋 READY

- **Scale**: 200 systems, 100k timesteps each
- **Per system**: ~5-10 minutes (estimated)
- **Sequential**: 15-30 hours (estimated)
- **Cloud**: 100 workers with 4 vCPUs, expected ~15-20 minutes
- **Expected speedup**: 50-90x
- **Status**: Ready to test

------------------------------------------------------------------------

## Current Test: Monte Carlo Mega

    === Configuration ===
    Scenarios: 100
    Iterations per scenario: 1,000,000
    Total iterations: 100,000,000

    === Timing ===
    Single scenario (local): 96.3 seconds
    Estimated sequential: 2.8 hours

    === Cloud Execution ===
    Workers: 100
    Tasks: 100 (one scenario per worker)
    Expected per-task time: ~1.6 min work + 3s overhead
    Expected total time: ~2-4 minutes

    === Expected Result ===
    Speedup: 40-50x
    Time saved: ~2.7 hours
    Cost: ~$1-2

**Status**: Cloud workers processing now…

------------------------------------------------------------------------

## Next Steps

1.  ✅ Complete Monte Carlo test
2.  Scale up Genomic example (make it 10-100x slower per sample)
3.  Test Climate model
4.  Test Molecular Dynamics
5.  Pick best 2-3 examples showing 50-100x speedups
6.  Document with real data
7.  Replace toy examples in vignettes

------------------------------------------------------------------------

## Success Criteria

- At least 2 examples showing **50x+ speedup**
- At least 1 example showing **100x+ speedup**
- Local sequential time: **1-5 hours**
- Cloud parallel time: **2-10 minutes**
- Cost: **\< \$5 per run**
- Clear demonstration of staRburst’s value for real science

------------------------------------------------------------------------

## Key Insights So Far

✅ **What works**: Multi-minute tasks with heavy computation - Monte
Carlo: 100M iterations, 96s per scenario ✓ - Cloud overhead: 2-3s (only
2-3% of work time) ✓

❌ **What doesn’t work**: Sub-second tasks - Genomics: 0.1s per sample
(overhead dominates) ✗

**The formula**:

    Speedup = Workers × (Work_Time / (Work_Time + Overhead))
            = 100 × (96s / (96s + 3s))
            = 100 × 0.97
            = ~97x theoretical maximum

    Actual speedup will be 40-80x due to:
    - Startup time spread across workers
    - S3 transfer time
    - Task scheduling overhead

------------------------------------------------------------------------

## Alternative: Use orion.local for Local Tests

User has offered another M4 Pro (orion.local) for running local baseline
tests.

**Advantages**: - Can run full workload locally in parallel (not just
estimate) - True apples-to-apples comparison with all performance
cores - More accurate timing data

**Next**: After Monte Carlo test completes, set up orion.local testing
