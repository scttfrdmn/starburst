#!/bin/bash
# Run benchmarks on orion.local and with staRburst, then compare

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "======================================================================"
echo "staRburst Benchmark Suite"
echo "======================================================================"
echo ""

# Check if orion.local is accessible
if ssh -o ConnectTimeout=5 orion.local 'echo OK' &>/dev/null; then
    ORION_AVAILABLE=true
    echo "✓ orion.local is accessible"
else
    ORION_AVAILABLE=false
    echo "⚠  orion.local not accessible, skipping remote benchmarks"
fi

echo ""

# 1. Run local sequential baseline
echo "1️⃣  Running LOCAL SEQUENTIAL benchmark..."
Rscript "$SCRIPT_DIR/benchmark-runner.R" local-seq

echo ""
echo "Press Enter to continue to next benchmark..."
read

# 2. Run local parallel on orion.local (if available)
if [ "$ORION_AVAILABLE" = true ]; then
    echo "2️⃣  Running LOCAL PARALLEL benchmark on orion.local..."

    # Copy script to orion
    scp "$SCRIPT_DIR/benchmark-runner.R" orion.local:/tmp/

    # Run on orion
    ssh orion.local "cd /tmp && Rscript benchmark-runner.R local-par"

    # Copy results back
    scp orion.local:/tmp/benchmark-results-local-parallel-*.rds "$SCRIPT_DIR/"

    echo "✓ Results copied back from orion.local"
else
    echo "2️⃣  Running LOCAL PARALLEL benchmark on this machine..."
    Rscript "$SCRIPT_DIR/benchmark-runner.R" local-par
fi

echo ""
echo "Press Enter to continue to cloud benchmarks..."
read

# 3. Run EC2 x86_64 benchmark
echo "3️⃣  Running EC2 x86_64 benchmark (c6a.large)..."
Rscript "$SCRIPT_DIR/benchmark-runner.R" ec2

echo ""
echo "Press Enter to continue..."
read

# 4. Run EC2 ARM64 benchmark
echo "4️⃣  Running EC2 ARM64 benchmark (c7g.xlarge Graviton)..."
Rscript "$SCRIPT_DIR/benchmark-runner.R" ec2-arm64

echo ""
echo "Press Enter to continue..."
read

# 5. Run EC2 Spot benchmark
echo "5️⃣  Running EC2 SPOT benchmark (c6a.large)..."
Rscript "$SCRIPT_DIR/benchmark-runner.R" ec2-spot

echo ""
echo "======================================================================"
echo "All benchmarks complete!"
echo "======================================================================"
echo ""

# Compare results
echo "Generating comparison report..."
Rscript "$SCRIPT_DIR/benchmark-runner.R" compare

echo ""
echo "✓ Benchmark files saved in $SCRIPT_DIR"
echo "✓ View results with: Rscript benchmark-runner.R compare"
echo ""
