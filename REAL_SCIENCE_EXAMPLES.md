# Real Science Examples - Publication-Grade Workloads

**Created**: 2026-02-04 **Purpose**: Demonstrate staRburst’s power with
truly massive scientific computing workloads

## Philosophy

Previous examples were “toys” - tasks that complete in seconds or
minutes locally. These examples are **REAL SCIENCE** that would take
**hours** running on M4 Pro performance cores, saturating all cores and
making the laptop run hot.

## Target Performance Profile

- **Local execution**: 1-2+ hours on M4 Pro (8-10 performance cores at
  100%)
- **Cloud execution**: 15-60 minutes with 50-100 workers
- **Target speedup**: 50-100x
- **Per-worker task time**: 2-10 minutes (overhead negligible)

## Three Examples

### 1. Genomic Variant Analysis (`real-science-genomics.R`)

**Scientific Domain**: Bioinformatics, Population Genetics

**Workload**: - 1,000 patient genomic samples - 50,000 variants per
sample (SNPs, indels) - 20,000 genes - Total: 50 million variant calls

**Analyses Per Sample**: 1. Allele frequency calculation 2.
Hardy-Weinberg Equilibrium testing (1,000 variants) 3. Linkage
Disequilibrium (500 variant pairs) 4. Gene-based association tests
(5,000 genes) 5. Population stratification (PCA on 1,000 variants)

**Computational Characteristics**: - Heavy matrix operations -
Statistical testing (chi-square, correlation) - Aggregations and
grouping - Per-sample time: ~30-60 seconds - Total sequential: ~10-15
hours

**Cloud Strategy**: - Batch 10 samples per worker - 100 workers - Each
worker: ~5-10 minutes - Expected speedup: 60-90x

**Real-World Application**: - GWAS (Genome-Wide Association Studies) -
Population genetics research - Clinical variant interpretation -
Personalized medicine

------------------------------------------------------------------------

### 2. Climate Model Ensemble (`real-science-climate.R`)

**Scientific Domain**: Climate Science, Earth System Modeling

**Workload**: - 500 climate model simulations (ensemble) - 100 years per
simulation - 100×100 spatial grid (10,000 cells) - 4 variables:
Temperature, Pressure, Humidity, Wind - Total: 5 billion cell-years

**Physical Processes**: 1. Spatial diffusion (heat/pressure
redistribution) 2. Coupled variable interactions 3. Forcing scenarios
(CO₂, solar) 4. Annual and decadal trend calculation 5. Extreme event
detection

**Computational Characteristics**: - Nested loops (years × months ×
spatial grid) - Neighbor averaging (convolution-like) - Time series
analysis - Linear regression for trends - Per-simulation time: ~3-5
minutes - Total sequential: ~25-40 hours

**Cloud Strategy**: - Batch 5 simulations per worker - 100 workers -
Each worker: ~15-25 minutes - Expected speedup: 60-100x

**Real-World Application**: - IPCC climate projections - Regional
climate modeling - Climate sensitivity studies - Uncertainty
quantification

------------------------------------------------------------------------

### 3. Molecular Dynamics Simulation (`real-science-molecular-dynamics.R`)

**Scientific Domain**: Computational Chemistry, Drug Discovery

**Workload**: - 200 protein-ligand systems - 10,000 atoms per system -
100,000 timesteps (100 picoseconds) - Total: 200 trillion force
calculations

**Physical Simulation**: 1. Pairwise force calculations (Lennard-Jones)
2. Velocity Verlet integration 3. Periodic boundary conditions 4. Energy
conservation monitoring 5. Structural analysis (radius of gyration)

**Computational Characteristics**: - **N² complexity** (pairwise
interactions) - Pure CPU burn (minimal I/O) - Floating-point intensive -
Memory-intensive (atom positions/velocities) - Per-system time: ~5-10
minutes - Total sequential: ~15-30 hours

**Cloud Strategy**: - Batch 2 systems per worker - 100 workers with 4
vCPU each - Each worker: ~10-20 minutes - Expected speedup: 50-90x

**Real-World Application**: - Drug discovery (protein-ligand binding) -
Protein folding studies - Material science simulations - Enzyme
mechanism research

------------------------------------------------------------------------

## Why These Work for staRburst

### Per-Task Duration: 2-10 Minutes

Each worker processes enough work (batched operations or long
simulations) to make the 2-3 second cloud overhead negligible:

| Example   | Work per Task         | Overhead | Overhead % |
|-----------|-----------------------|----------|------------|
| Genomics  | 5-10 min (10 samples) | 3s       | 0.5-1%     |
| Climate   | 15-25 min (5 sims)    | 3s       | 0.2-0.3%   |
| Molecular | 10-20 min (2 sims)    | 3s       | 0.3-0.5%   |

### Computation Dominates I/O

All three examples are **compute-bound**, not I/O-bound: - Minimal data
transfer (small input parameters) - Heavy computation on workers - Small
result objects returned - Perfect fit for Fargate’s CPU

### Realistic Scientific Scale

These aren’t contrived examples - they represent actual
publication-grade science: - Genomics: Real GWAS sample sizes (hundreds
to thousands) - Climate: Standard ensemble sizes (hundreds of runs) -
Molecular: Typical high-throughput screening (hundreds of ligands)

------------------------------------------------------------------------

## Testing Strategy

### Phase 1: Single-Item Timing

Test one sample/simulation locally to establish per-item time:

``` r
single_start <- Sys.time()
result <- analyze_one_sample(1)
single_time <- difftime(Sys.time(), single_start, units = "secs")
```

### Phase 2: Local Estimate

Run a small subset (2-5 items) to confirm timing and estimate total:

``` r
local_estimated <- single_time * n_total_items
# Expected: 1-2+ hours
```

### Phase 3: Cloud Execution

Run full workload with proper batching and worker count:

``` r
cloud_results <- starburst_map(
  batches,
  process_batch,
  workers = 50-100
)
# Expected: 15-60 minutes
```

### Phase 4: Validate Speedup

``` r
speedup <- local_estimated / cloud_time
# Expected: 50-100x
```

------------------------------------------------------------------------

## Cost Estimates

### Genomics Example

- Workers: 100 × 2 vCPU × 4 GB
- Duration: ~10 minutes
- Cost: ~\$0.50-1.00
- **Cost per hour saved**: ~\$0.05-0.10

### Climate Example

- Workers: 100 × 2 vCPU × 4 GB
- Duration: ~20 minutes
- Cost: ~\$1.00-2.00
- **Cost per hour saved**: ~\$0.05-0.08

### Molecular Dynamics Example

- Workers: 100 × 4 vCPU × 8 GB (more intensive)
- Duration: ~15 minutes
- Cost: ~\$2.00-4.00
- **Cost per hour saved**: ~\$0.10-0.20

All examples cost **pennies per hour saved** - excellent value for
research computing.

------------------------------------------------------------------------

## Comparison to Original Examples

| Metric            | Original Examples       | Real Science Examples |
|-------------------|-------------------------|-----------------------|
| Local time        | 1-5 minutes             | 1-2+ hours            |
| Cloud speedup     | 1-4x (or negative!)     | 50-100x               |
| Per-task duration | 0.5-2 seconds           | 2-10 minutes          |
| Overhead impact   | 200% (overhead \> work) | \<1% (negligible)     |
| Laptop thermal    | Cool                    | Would melt 🔥         |
| Scientific value  | Demo only               | Publication-grade     |

------------------------------------------------------------------------

## Key Insights

1.  **Scale Matters**: Cloud parallel computing needs sufficient scale
    to overcome overhead
2.  **Batching is Critical**: Group operations to create multi-minute
    tasks
3.  **Compute-Bound Wins**: CPU-intensive workloads are ideal
4.  **Real Science = Real Speedup**: Publication-grade workloads
    naturally fit the model

------------------------------------------------------------------------

## Next Steps

1.  ✅ Create three massive scientific examples
2.  ⏳ Test locally to confirm ~1-2 hour sequential time on M4 Pro
3.  ⏳ Test on AWS to confirm 50-100x speedup
4.  ⏳ Document actual timing and cost data
5.  Update vignettes with real results
6.  Replace toy examples with these in documentation

------------------------------------------------------------------------

## Notes

- These examples saturate M4 Pro performance cores
- Local execution will make laptop hot and slow
- Cloud execution keeps laptop cool and completes much faster
- Perfect demonstration of staRburst’s value proposition
- Shows why researchers need cloud parallel computing

**This is the real power of staRburst.**
