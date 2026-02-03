#!/bin/bash
# Run all staRburst examples
#
# Usage:
#   ./run-all-examples.sh local              # Run locally (baseline)
#   ./run-all-examples.sh aws [workers]      # Run on AWS with N workers

set -e

MODE="${1:-local}"
WORKERS="${2:-50}"

echo "================================"
echo "staRburst Examples Test Suite"
echo "================================"
echo "Mode: $MODE"
if [ "$MODE" = "aws" ]; then
  echo "Workers: $WORKERS"
  export USE_STARBURST=TRUE
  export STARBURST_WORKERS=$WORKERS
  export AWS_PROFILE="${AWS_PROFILE:-aws}"
else
  export USE_STARBURST=FALSE
fi
echo ""

# Create results directory
RESULTS_DIR="example-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "Results will be saved to: $RESULTS_DIR"
echo ""

# Track overall timing
OVERALL_START=$(date +%s)

# Array of examples
examples=(
  "01-monte-carlo-portfolio.R"
  "02-bootstrap-confidence-intervals.R"
  "03-parallel-data-processing.R"
  "04-grid-search-tuning.R"
)

# Run each example
for example in "${examples[@]}"; do
  echo "========================================"
  echo "Running: $example"
  echo "========================================"
  echo ""

  START=$(date +%s)

  if Rscript "examples/$example" 2>&1 | tee "$RESULTS_DIR/${example%.R}.log"; then
    END=$(date +%s)
    ELAPSED=$((END - START))
    echo ""
    echo "✓ Completed in ${ELAPSED}s"

    # Move result files to results directory
    mv *-results-*.rds "$RESULTS_DIR/" 2>/dev/null || true
  else
    echo ""
    echo "✗ Failed!"
    exit 1
  fi

  echo ""
done

OVERALL_END=$(date +%s)
OVERALL_ELAPSED=$((OVERALL_END - OVERALL_START))

echo "========================================"
echo "All Examples Complete"
echo "========================================"
echo "Total time: ${OVERALL_ELAPSED}s ($((OVERALL_ELAPSED / 60))m)"
echo "Results saved to: $RESULTS_DIR"
echo ""

# Summary
echo "Summary:"
echo "--------"
for example in "${examples[@]}"; do
  logfile="$RESULTS_DIR/${example%.R}.log"
  if [ -f "$logfile" ]; then
    # Extract execution time from log
    time=$(grep "Execution time:" "$logfile" | head -1 || echo "N/A")
    echo "  ${example}: $time"
  fi
done
echo ""
echo "See detailed logs in $RESULTS_DIR/"
