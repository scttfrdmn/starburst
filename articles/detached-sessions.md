# Detached Session Mode

## Detached Sessions

Detached sessions allow you to start long-running computations in AWS,
safely close your R session, and reattach later to check progress and
collect results.

### Why Use Detached Sessions?

For analyses that take hours or days:

- **Start and detach**: Launch your computation and close your laptop
- **Reattach anytime**: Check progress from any R session
- **Fault tolerant**: Your computations continue even if your local R
  crashes
- **Cost efficient**: Workers auto-scale down when idle

### Basic Usage

#### Creating a Session

``` r

library(starburst)

# Create a detached session (EC2 workers with Spot by default)
session <- starburst_session(
  workers = 10,
  cpu = 4,
  memory = "8GB"
)

# Submit tasks
task_ids <- lapply(1:100, function(i) {
  session$submit(quote({
    # Your long-running computation
    result <- expensive_analysis(i)
    result
  }))
})

# Save session ID for later
session_id <- session$session_id
print(session_id)  # "session-abc123..."
```

#### Checking Status

``` r

# Check progress anytime
status <- session$status()
print(status)
# Session Status:
#   Total tasks:     100
#   Pending:         25
#   Running:         10
#   Completed:       60
#   Failed:          5
#   Progress:        60.0%
```

#### Collecting Results

``` r

# Collect completed results (non-blocking)
results <- session$collect(wait = FALSE)
length(results)  # 60 (only completed so far)

# Or wait for all to complete
results <- session$collect(wait = TRUE, timeout = 3600)
length(results)  # 100 (all tasks)
```

### Detach and Reattach

Close R and come back later:

``` r

# Session 1: Start work
session <- starburst_session(workers = 20)
lapply(1:1000, function(i) session$submit(quote(slow_computation(i))))
session_id <- session$session_id

# Close R, go home, come back tomorrow...

# Session 2: Reattach
session <- starburst_session_attach(session_id)
status <- session$status()
results <- session$collect()
```

### Session Management

#### List All Sessions

``` r

sessions <- starburst_list_sessions()
print(sessions)
#   session_id         created_at           last_activity        total_tasks pending running completed failed
#   session-abc123     2026-02-06 10:00:00  2026-02-06 10:15:00  100         0       5       90        5
#   session-def456     2026-02-05 14:30:00  2026-02-05 18:45:00  500         0       0       500       0
```

#### Extend Timeout

``` r

# Extend session timeout by 1 hour
session$extend(seconds = 3600)
```

#### Cleanup

``` r

# Stop workers and mark the session terminated. S3 objects are PRESERVED by
# default, so you can still reattach and collect afterwards.
session$cleanup()

# To also delete the session's S3 task/result objects, pass force = TRUE:
session$cleanup(force = TRUE)
```

### Choosing and tuning the backend

Sessions use **EC2 with Spot instances by default** — no extra arguments
needed. You can tune the instance type, or opt into Fargate. A
non-default instance type is provisioned automatically on first use (a
one-time ~1–2 min step), or run
`starburst_setup_ec2(instance_types = "c8a.xlarge")` once to
pre-provision it.

``` r

# Default is already EC2 + Spot (c7g.xlarge); override the instance type if you like
session <- starburst_session(
  workers = 50,
  instance_type = "c8a.xlarge",  # AMD 8th gen; auto-provisioned on first use
  use_spot = TRUE                 # default TRUE — ~70% cheaper
)

# Opt into the Fargate backend (serverless, task-based) instead
session <- starburst_session(
  workers = 50,
  launch_type = "FARGATE"
)
```

### Advanced Usage

#### Error Handling

``` r

# Tasks that fail are tracked, not silently dropped
session <- starburst_session(workers = 5)

task_ids <- lapply(1:10, function(i) {
  session$submit(quote({
    if (i == 5) stop("Intentional error")
    i * 2
  }), globals = list(i = i))
})

# Check status
status <- session$status()
print(status)   # Failed: 1

# collect() returns an entry for EVERY task, keyed by task id. A failed task
# comes back as a structured failure (error = TRUE) alongside the successes.
results <- session$collect(wait = TRUE)

# Separate successes from failures
failures <- Filter(function(r) isTRUE(r$error), results)
length(failures)                 # 1
print(failures[[1]]$message)     # "Intentional error"

# Successful values are the non-error entries
successes <- Filter(function(r) !isTRUE(r$error), results)
```

#### Partial Collection

Collect results as they complete:

``` r

session <- starburst_session(workers = 10)

# Submit mix of fast and slow tasks
lapply(1:5, function(i) session$submit(quote(i * 2)))        # Fast
lapply(1:5, function(i) session$submit(quote({ Sys.sleep(60); i })))  # Slow

Sys.sleep(10)

# Get fast results immediately
results <- session$collect(wait = FALSE)
length(results)  # 5 (fast tasks done)

# Later, get remaining results
Sys.sleep(60)
results <- session$collect(wait = FALSE)
length(results)  # 10 (all done)
```

### How It Works

#### Architecture

1.  **S3 State Persistence**: All session state lives in S3
    - Session manifest: configuration and statistics
    - Task statuses: pending → claimed → running → completed
    - Results: stored per task
2.  **Worker Polling**: Workers continuously poll for pending tasks
    - Exponential backoff: 1s → 2s → 4s → … → 30s
    - Atomic task claiming using S3 ETags
    - Self-terminate after 5 minutes idle
3.  **Atomic Task Claiming**: No duplicate execution
    - Workers use conditional S3 writes with ETags
    - Only one worker can claim each task
    - Prevents race conditions

#### Task Lifecycle

    pending → claimed → running → completed
                             ↓
                          failed

Each state transition is recorded in S3 with timestamps.

### Best Practices

#### When to Use Detached Sessions

✅ **Good use cases:** - Long-running analyses (hours to days) -
Computations you want to monitor remotely - Jobs that might exceed your
local R session lifetime - Analyses you want to inspect partially before
completion

❌ **Not ideal for:** - Quick computations (\< 5 minutes) - Interactive
workflows requiring immediate feedback - Tasks with millisecond-level
coordination requirements

#### Resource Management

``` r

# Start with fewer workers, let them process queue
session <- starburst_session(workers = 5)

# Submit large batch
lapply(1:1000, function(i) session$submit(quote(work(i))))

# Workers process tasks continuously until queue empty
# Then auto-terminate after 5 min idle
```

#### Cost Optimization

1.  **Use EC2 + Spot** for long-running batch jobs (70% cheaper)
2.  **Set appropriate timeouts** to avoid idle costs
3.  **Collect results incrementally** to monitor progress
4.  **Clean up sessions** when done

``` r

# Cost-effective setup
session <- starburst_session(
  workers = 20,
  launch_type = "EC2",
  instance_type = "c8a.xlarge",
  use_spot = TRUE,
  session_timeout = 3600,
  absolute_timeout = 86400
)
```

### Comparison: Ephemeral vs Detached

| Feature | Ephemeral (`plan(starburst)`) | Detached ([`starburst_session()`](https://starburst.ing/reference/starburst_session.md)) |
|----|----|----|
| R session required | Yes - must stay open | No - can close and reattach |
| State persistence | In-memory only | S3-backed |
| Max duration | R session lifetime | Days (configurable) |
| Progress monitoring | Local variables | `session$status()` |
| Worker behavior | One task per worker | Workers poll for tasks |
| Best for | Quick parallel jobs | Long-running analyses |

### Troubleshooting

#### Session Not Found

``` r

# Error: Session not found: session-xyz
# - Check session ID is correct
# - Verify region matches (use region parameter)
# - Session may have expired (check absolute_timeout)
```

#### No Results After Long Wait

``` r

# Check session status
status <- session$status()

# If pending tasks stuck:
# - Workers may have terminated (check idle timeout)
# - Launch more workers: (not yet implemented)
# - Check CloudWatch logs: starburst_logs(session_id)
```

#### Workers Terminating Too Soon

``` r

# Workers exit after 5 min idle by default
# For sporadic task submission, relaunch workers periodically
# (Auto-scaling based on pending tasks coming in future release)
```

### Examples

#### Genomics Pipeline

``` r

library(starburst)

# Process 1000 samples overnight
session <- starburst_session(
  workers = 100,
  cpu = 8,
  memory = "32GB",
  launch_type = "EC2",
  use_spot = TRUE
)

# Submit all samples
sample_files <- list.files("samples/", pattern = "*.fastq")
task_ids <- lapply(sample_files, function(file) {
  session$submit(quote({
    library(Rsubread)
    results <- align_and_quantify(file)
    save_results(results, file)
    results
  }))
})

# Check progress next morning
session <- starburst_session_attach(session$session_id)
status <- session$status()
# Completed: 950, Running: 45, Failed: 5

results <- session$collect(wait = TRUE)
```

#### Monte Carlo Simulation

``` r

# Run 10,000 simulations
session <- starburst_session(workers = 50)

n_sims <- 10000
lapply(1:n_sims, function(i) {
  session$submit(quote({
    set.seed(i)
    run_simulation()
  }))
})

# Check progress periodically
repeat {
  status <- session$status()
  print(sprintf("Progress: %.1f%%", 100 * status$completed / status$total))

  if (status$completed == n_sims) break
  Sys.sleep(60)
}

results <- session$collect()
```

### See Also

- [`?starburst_session`](https://starburst.ing/reference/starburst_session.md) -
  Create detached session
- [`?starburst_session_attach`](https://starburst.ing/reference/starburst_session_attach.md) -
  Reattach to session
- [`?starburst_list_sessions`](https://starburst.ing/reference/starburst_list_sessions.md) -
  List all sessions
- `vignette("staRburst")` - General usage guide
