#!/usr/bin/env Rscript

# ============================================================================
# THE WINNING SCENARIO: Heavy Batching Strategy
# ============================================================================
#
# This example demonstrates the optimal batching strategy:
# - Process 1000 data chunks (1.5s each = 1500s total work)
# - Batch into 20 groups of 50 chunks each
# - Each batch takes ~75 seconds (50 × 1.5s)
# - Cloud overhead (2-3s) is only 3-4% of work time
# - Expected speedup: 15-20x with 20 workers
#
# The key: Each worker processes 50 operations in a single task!
# ============================================================================

suppressPackageStartupMessages({
  library(starburst)
})

cat("=== WINNING SCENARIO: Heavy Batching for Maximum Speedup ===\n\n")

# Configuration
total_chunks <- 1000
chunks_per_batch <- 50
n_batches <- total_chunks / chunks_per_batch

cat("Processing", total_chunks, "data chunks\n")
cat("Batching:", n_batches, "batches of", chunks_per_batch, "chunks each\n")
cat("Expected per-batch time: ~75 seconds (", chunks_per_batch, "× 1.5s)\n\n")

# Realistic data processing function
process_chunk <- function(chunk_id) {
  # Simulate realistic data processing
  # Each chunk: 10k rows, 5 operations
  n <- 10000

  # Operation 1: Data generation
  data <- data.frame(
    id = 1:n,
    value1 = rnorm(n),
    value2 = rnorm(n),
    category = sample(LETTERS[1:5], n, replace = TRUE)
  )

  # Operation 2: Feature engineering
  data$ratio <- data$value1 / (abs(data$value2) + 0.1)
  data$interaction <- data$value1 * data$value2

  # Operation 3: Aggregation
  agg <- aggregate(cbind(value1, value2, ratio) ~ category, data, mean)

  # Operation 4: Statistical test
  test_results <- lapply(unique(data$category), function(cat) {
    subset_data <- data[data$category == cat, ]
    list(
      category = cat,
      mean = mean(subset_data$ratio),
      sd = sd(subset_data$ratio),
      n = nrow(subset_data)
    )
  })

  # Operation 5: Summary
  list(
    chunk_id = chunk_id,
    n_rows = n,
    aggregates = agg,
    tests = test_results
  )
}

# Batch processing function (runs on each worker)
process_batch <- function(chunk_ids) {
  lapply(chunk_ids, process_chunk)
}

# Test single chunk timing
cat("Testing single chunk timing...\n")
single_start <- Sys.time()
test_result <- process_chunk(1)
single_time <- as.numeric(difftime(Sys.time(), single_start, units = "secs"))
cat(sprintf("Single chunk: %.2f seconds\n\n", single_time))

# LOCAL: Process subset sequentially
local_subset <- 20
cat(sprintf("LOCAL: Processing %d chunks to estimate full time...\n", local_subset))
local_start <- Sys.time()
local_results <- lapply(1:local_subset, process_chunk)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
local_per_chunk <- local_time / local_subset
local_estimated <- local_per_chunk * total_chunks

cat(sprintf("✓ %d chunks in %.1f seconds\n", local_subset, local_time))
cat(sprintf("  Per chunk: %.2f seconds\n", local_per_chunk))
cat(sprintf("  Estimated for %d: %.1f seconds (%.1f minutes)\n\n",
            total_chunks, local_estimated, local_estimated / 60))

# Create batches
batches <- split(1:total_chunks, ceiling(seq_along(1:total_chunks) / chunks_per_batch))

# CLOUD: Process all batches in parallel
n_workers <- length(batches)  # One batch per worker
cat(sprintf("CLOUD: Processing %d batches with %d workers...\n",
            length(batches), n_workers))
cat(sprintf("Each worker processes %d chunks (~%.0f seconds)\n\n",
            chunks_per_batch, chunks_per_batch * single_time))

cloud_start <- Sys.time()
cloud_results <- starburst_map(
  batches,
  process_batch,
  workers = n_workers
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("✓ Completed in %.1f seconds (%.1f minutes)\n\n",
            cloud_time, cloud_time / 60))

# Results
speedup <- local_estimated / cloud_time
time_saved <- local_estimated - cloud_time
efficiency <- (speedup / n_workers) * 100

cat("╔══════════════════════════════════════════════════╗\n")
cat("║        HEAVY BATCHING RESULTS                    ║\n")
cat("╚══════════════════════════════════════════════════╝\n\n")

cat(sprintf("Total chunks processed: %d\n", total_chunks))
cat(sprintf("Batches: %d batches of %d chunks\n\n", length(batches), chunks_per_batch))

cat("┌────────────────────────────────────────────────┐\n")
cat("│ PERFORMANCE COMPARISON                         │\n")
cat("├────────────────────────────────────────────────┤\n")
cat(sprintf("│ Local (estimated): %.1f min               │\n", local_estimated / 60))
cat(sprintf("│ Cloud (%d workers): %.1f min              │\n", n_workers, cloud_time / 60))
cat(sprintf("│ Speedup: %.1fx                            │\n", speedup))
cat(sprintf("│ Time saved: %.1f minutes                  │\n", time_saved / 60))
cat(sprintf("│ Efficiency: %.0f%% of ideal (%dx workers) │\n", efficiency, n_workers))
cat("└────────────────────────────────────────────────┘\n\n")

cat("┌────────────────────────────────────────────────┐\n")
cat("│ WHY THIS WORKS                                 │\n")
cat("├────────────────────────────────────────────────┤\n")
cat(sprintf("│ Work per batch: ~%.0f seconds              │\n", chunks_per_batch * single_time))
cat("│ Cloud overhead: ~2-3 seconds                   │\n")
cat(sprintf("│ Overhead impact: %.1f%%                     │\n",
            (3 / (chunks_per_batch * single_time)) * 100))
cat("└────────────────────────────────────────────────┘\n\n")

cat("✓ Heavy batching completed!\n\n")

if (speedup >= 15) {
  cat(sprintf("🎉 Achieved %.1fx speedup - batching strategy works!\n", speedup))
} else if (speedup >= 10) {
  cat(sprintf("✓ Good %.1fx speedup - consider larger batches for more\n", speedup))
} else {
  cat(sprintf("⚠️  Only %.1fx speedup - batches may still be too small\n", speedup))
}
