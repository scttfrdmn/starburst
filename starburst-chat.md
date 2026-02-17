# Async - returns immediately

Question - I am thinking about creating an extension for R (Studio)
where I can spawn off execution to AWS. I do not want to run R (Studio)
on AWS just burst/offload to AWS

Jan 30

Examined distributed computing frameworks and architected cloud-burst
solutions This is a great idea and aligns well with your cloud economics
work! There are a few architectural approaches to consider:

Existing R Ecosystem The future package is probably your best starting
point. It provides a unified API for parallel/distributed computing in
R, and you could create a custom backend that submits to AWS. The
future.batchtools package already does something similar for traditional
HPC schedulers - you’d essentially build future.aws or similar.

Architecture Options 1. AWS Batch-based

Serialize R objects + code to S3 Submit AWS Batch job with your R
environment Job pulls data from S3, executes, writes results back Local
RStudio polls/receives completion notification Deserialize results 2.
Direct EC2 Spot

Lighter weight than Batch for some workloads Launch spot instance with R
pre-configured (AMI) SSH-based execution or HTTP API More control over
instance lifecycle 3. Lambda for lightweight tasks

Limited to 15 min, 10GB memory Could work for embarrassingly parallel
map operations Need custom R runtime layer Key Challenges Data
serialization: R’s native serialization can be inefficient for large
objects. Consider qs package (much faster than saveRDS) or Apache Arrow
for data frames.

Environment consistency: Your local R environment needs to match remote.
Docker images or reproducible environments (renv/packrat) are critical.

Cost optimization: This is where your queueing theory work becomes
really interesting - the economics of bursting vs keeping warm instances
vs cold starts.

Would you want this to handle both interactive bursting (wait for
results) and async batch jobs? And are you thinking primarily about
embarrassingly parallel workloads or also complex dependencies?

Both. I want it to be seamless

Jan 31

Synthesized interactive and asynchronous compute integration leveraging
cloud infrastructure expertise Now we’re talking about something
interesting. “Seamless” means the abstraction needs to be really good.
Let me sketch what this could look like:

User Experience Target r \# Interactive - blocks until complete result
\<- aws_burst({ expensive_model_fit(large_data) }, instance = “auto”) \#
or “c5.4xlarge”, “g4dn.xlarge”, etc.

job \<- aws_burst_async({ monte_carlo_simulation(1e6) }) \# … do other
work … result \<- await(job) \# or value(job) if using future API
Architecture for Seamless Experience Smart instance selection: This is
where your queueing theory work becomes the product. Don’t make users
think about instance types - analyze their code/data characteristics and
pick optimal instance:

Memory footprint → instance size CPU vs GPU operations → instance family
Estimated runtime → spot vs on-demand decision Historical patterns →
warm pool management Transparent environment sync:

Snapshot local R environment (renv) on first use Build Docker image or
use Lambda layers Cache on ECR, reuse across invocations Only rebuild
when packages change Fast data movement:

Leverage your CargoShip S3 optimization Intelligent serialization (qs
for R objects, Arrow for data frames) Streaming results for large
outputs Compression based on data type Cost intelligence built-in:

Show cost estimate before execution Integrate with your bank-and-burst
tooling Automatic spot/on-demand decisions based on interruption risk
Usage tracking that feeds your cloud economics models The Differentiator
What makes this different from “just run RStudio Server on EC2” is the
cognitive load. Researchers don’t want to:

Think about instances Manage infrastructure Context-switch to AWS
console Debug remote environments Your tool handles all that. They stay
in their local RStudio workflow, and expensive operations “just happen
faster.”

Big question: For the interactive case, how do you handle the cold start
problem? Even spot instances take 60-90 seconds to launch. Do you:

Keep a warm pool - costs money but immediate response Accept the startup
latency - cheaper but breaks “seamless” Hybrid - predictive warm pools
based on usage patterns Given your queueing theory background, option 3
is probably the interesting one - you could model usage patterns and
optimize the warm pool size dynamically.

What’s your tolerance for startup latency in the interactive case?

What about fargate?

Jan 31

Weighed Fargate’s serverless benefits against cost and constraint
tradeoffs Fargate is actually perfect for this.

Why Fargate Fits Startup time: ~30-60 seconds for cold start (vs 90+ for
EC2 Spot). Still not instant, but acceptable for most “burst” scenarios
where you’re offloading something that would take minutes/hours locally.

No warm pool complexity: You don’t have to solve the queueing theory
problem of maintaining a warm pool. AWS handles container orchestration.
This dramatically simplifies your architecture.

Cost model: More expensive per compute-hour than Spot (~3-4x), but you
only pay for actual execution time. For bursty workloads where you’d
otherwise keep instances warm, the economics can actually work out
better.

Resource limits: 16 vCPU, 120GB RAM covers probably 90% of R workloads.
The 10% that need more (huge genomics datasets, giant model fits) could
fall back to EC2 Batch.

Architecture with Fargate Local RStudio → Package R code + data → S3 →
Trigger ECS Fargate task → Task pulls from S3, executes, writes results
→ S3 → Notification (EventBridge → SNS → local polling) → Deserialize
results Simple version:

Single Fargate task definition with R + common packages User code runs
in container Returns results via S3 Better version:

Generate task definition on-the-fly based on resource needs Use your
renv snapshot to build container layers Intelligent sizing (Fargate has
discrete CPU/memory combos) When to NOT use Fargate GPU workloads -
Fargate doesn’t support GPUs. Need EC2 g4dn/p3/etc instances. Massive
memory (\>120GB) - Rare but happens Extremely long-running (\>hours)
where Spot pricing matters Super-latency-sensitive interactive work
Hybrid Approach r \# Fargate by default - handles 90% of cases result
\<- aws_burst({ slow_computation() })

# Explicit EC2 for edge cases

result \<- aws_burst({ gpu_model_training() }, backend = “ec2-spot”,
instance = “g4dn.xlarge”) The beauty is Fargate becomes your default
path because it’s operationally simple, and you only add complexity (EC2
instance management, warm pools, spot bidding) when the workload
actually needs it.

Does Fargate’s 30-60s cold start feel acceptable for your “seamless”
requirement? If so, this dramatically simplifies what you’re building.

Seamless to me is invisible, just works, no concern. The tool could also
be smart about whether execution on AWS is worth it. If the work would
only take 2m why bother. Plus the latency could be hidden locally

Jan 31

Synthesized intelligent routing logic balancing local and cloud
execution costs Now you’re describing the real product. This isn’t just
“run R code on AWS” - it’s an intelligent execution optimizer that
happens to use AWS.

Smart Decision Framework r \# User doesn’t specify anything result \<-
compute({ expensive_operation(data) })

    Behind the scenes, the tool decides:

    **1. Profile the workload** (lightweight, runs locally):
    - Estimated memory footprint
    - CPU intensity (vectorized? parallel?)
    - Data transfer size
    - Historical timing if seen before

    **2. Decision matrix**:

Local execution time estimate: 2min Cloud execution time: 5min compute +
45s startup + 20s data transfer Cloud cost: \$0.12 → Decision: LOCAL
(not worth 45s startup overhead)

Local execution time estimate: 45min  
Cloud execution time: 8min compute + 45s startup + 20s data transfer
Cloud cost: \$0.85 → Decision: CLOUD (saves 36min for \$0.85)

    **3. Speculative execution** (the clever bit):

Estimated local: 12min Estimated cloud: 6min + 45s overhead

→ Start BOTH → Fargate spins up (45s) → Local runs for 45s → Cloud
starts at 0:45, local at ~5min done → Cloud finishes at ~7min → Use
local result, cancel cloud (or vice versa) Latency Hiding Strategies
Background execution:

For anything \>5min estimated, just start Fargate in background Show
progress locally Switch to cloud result when ready User never “waits”
for startup Progressive enhancement:

Start local on small data sample If taking too long, spin up cloud for
full dataset Show early results while cloud crunches Learning system:

Track actual vs estimated times Build user-specific execution profiles
“Your genomics pipelines usually take 4x longer than you think and cost
\$2.50 on cloud - auto-bursting by default now” The Economics Engine
This is where your cloud economics work becomes the core differentiator.
The tool embeds your queueing theory insights:

r \# Configuration once aws_burst_config( hourly_rate = 75, \# my time
value local_cores = 16, local_memory = 64, acceptable_cost = 5, \#
willing to spend \$5 to save time impatience_factor = 0.8 \# heavily
value time savings )

# Now the tool optimizes for YOUR utility function

Decision factors:

Direct compute cost Data transfer cost Your time value (opportunity
cost) Current local machine load Urgency (interactive vs batch)
Implementation Strategy Phase 1: Simple threshold

If estimated local time \> 10min → cloud Else → local Phase 2:
Cost-benefit

Factor in cloud costs User-configurable time value Phase 3: Speculative
execution

Race local vs cloud Learning from historical patterns Phase 4: Portfolio
optimization

Multiple jobs? Optimize allocation across local + multiple cloud
instances This is literally queueing theory applied to personal
computing The Killer Feature Most “cloud burst” tools are just wrappers
around infrastructure. Yours understands economics. It’s the difference
between:

“I can run this on AWS”

vs

“This will save you 37 minutes and cost \$1.20 - running on cloud. Your
coffee break just got longer.”

Does this align with your vision? The economics intelligence layer is
what makes it genuinely seamless rather than just convenient.

Yes it does Question, is it possible to capture the state of a R
environment and transfer it to the cloud instance to pick up and carry
on? Kind of like migrating a running VM

Jan 31

Examined R session serialization feasibility and identified practical
limitations Sort of, but with important caveats.

What’s Possible You can capture and restore most of an R environment,
but it’s not quite like VM migration. Think of it more like “checkpoint
and resume” than “live migration.”

Can transfer:

Workspace objects (save.image() or better, qs::qsave()) Loaded packages
(capture with sessionInfo(), restore with library()) Global options
(options()) Random number generator state (.Random.seed) Search path
configuration Cannot cleanly transfer:

Active database connections (MySQL, PostgreSQL, etc.) Open file handles
Graphics devices External pointers (C/C++ memory from packages like
data.table, Rcpp) Network connections Parent R process context Practical
Approach r \# Locally - capture state snapshot \<- aws_checkpoint() \#
Behind the scenes: \# - qs::qsave(as.list(.GlobalEnv), “workspace.qs”)
\# - Capture loaded packages \# - Capture options, RNG state \# - Upload
to S3

# Cloud - restore state

aws_restore(snapshot) \# - Download from S3 \# - Load packages in order
\# - Restore workspace \# - Set options, RNG state The Real-World
Problem Most research workflows have implicit dependencies:

r \# Local session library(DBI) con \<- dbConnect(MySQL(), host =
“localhost”, …) data \<- dbGetQuery(con, “SELECT \* FROM big_table”)

# Now you want to burst this:

model \<- heavy_computation(data) \# \<– this could migrate

# But `con` is a connection object - can’t serialize

Smarter Solution: Code Migration, Not State Migration Instead of
migrating a running environment, migrate the recipe to recreate it:

r \# User writes aws_burst({ \# This block is self-contained
library(dplyr) library(ggplot2)

data \<- read_csv(“s3://bucket/data.csv”) \# data from S3, not local
connection result \<- expensive_model(data) result }) Your tool:

Captures closure: What objects from parent environment are needed?
Serializes dependencies: Any data objects referenced Reconstructs
environment cloud-side: Loads packages, injects objects Executes: Runs
the code block Returns: Serializes result back This is essentially what
future package does - it captures the closure and dependencies.

Hybrid: Smart Checkpoint For interactive workflows, you could do
something clever:

r \# User has been working locally data \<- expensive_data_prep() \#
took 30 min locally transformed \<- transform_data(data) \# another 20
min

# Now want to burst

aws_burst({ final_model \<- fit_model(transformed) \# this will take 2
hours final_model }) Behind the scenes:

Detect transformed is referenced from parent environment Serialize
transformed to S3 (using your CargoShip optimization) Cloud
reconstructs: transformed \<- qs::qread(“s3://…”) Runs model fitting
Returns result The Container Checkpoint Approach (Advanced) For true
“pause and resume”, you’d need CRIU (Checkpoint/Restore In Userspace) in
your Fargate container. This can snapshot a running process’s entire
memory state.

Pros: True live migration - pause R locally, resume on cloud Cons:

Heavy (multi-GB snapshots) Finicky with R’s complex runtime Fargate
doesn’t support CRIU directly Transfer time kills the benefit My
Recommendation Don’t try to migrate running state. Instead:

Make code blocks self-contained - users structure work as reproducible
chunks Auto-capture dependencies - your tool identifies and serializes
referenced objects Fast serialization - use qs + your S3 optimization
Smart about data - if data is already in S3, don’t round-trip it This
gives 90% of the benefit without the nightmare of trying to serialize
database connections and file handles.

Does that match your mental model, or were you hoping for true live
migration?

I was thinking more along the lines of your speculative execution Also
any code using a db would have trouble bursting to AWS anyway, it would
be better to have the db on AWS in the first place so it works locally
and on AWS

Jan 31

Reconciled speculative execution feasibility with database architecture
constraints Ah, you’re right on both counts.

Speculative Execution Clarification You’re talking about:

Time 0s: Start local AND start Fargate Time 0-45s: Local computes while
Fargate spins up Time 45s: Fargate ready - can it pick up from where
local got to? For most R computations, no - and it doesn’t matter.

Here’s why:

Atomic operations (most R work):

r result \<- lm(y ~ x1 + x2 + x3, data = huge_data) This is a single
matrix operation. There’s no “intermediate state” at 45s - it’s either
done or not. Can’t checkpoint halfway through a matrix inversion.

What DOES work:

r \# Iterative algorithm for (i in 1:1000) { model \<-
update_model(model, data) \# each iteration is checkpointable }

    At 45s local might be at iteration 50. You could transfer that state and have cloud continue from iteration 51. But the overhead of serialization + transfer probably eats any gain.

    ## Better Speculative Strategy

    **Simple race**:
    - Both start from scratch
    - First to finish wins, kill the other
    - Accept that one will be wasted compute

    **Why this is fine**:
    - 45s of local compute on your 16-core workstation ≈ $0.00 (already paid for)
    - If local finishes in <2min, cloud never gets used (Fargate billed per-second, minimal cost)
    - If job takes 30min, wasting 45s of local compute is noise

    **When to use which**:

Estimated time: 2-5 min → Local only (cloud overhead not worth it)

Estimated time: 5-15 min  
→ Speculative execution (hedge your bet)

Estimated time: \>15 min → Cloud only (clear winner, don’t waste local
cycles) Database Point is Key You’re absolutely right:

r \# BAD - won’t burst well con \<- dbConnect(RMySQL::MySQL(), host =
“localhost”, …) data \<- dbGetQuery(con, “SELECT \* FROM research_data”)
model \<- expensive_fit(data)

# GOOD - bursts cleanly

con \<- dbConnect(RMySQL::MySQL(), host =
“mydb.abc123.us-east-1.rds.amazonaws.com”, …) data \<- dbGetQuery(con,
“SELECT \* FROM research_data”)  
model \<- expensive_fit(data) \# \<- this bursts perfectly Both local
RStudio and Fargate hit the same RDS instance. No state transfer needed.

This actually simplifies your architecture:

Persistent data lives in AWS (S3, RDS) Both local and cloud are
stateless compute You’re just choosing the faster/cheaper compute
location The Real Value of Speculative Execution It’s not about state
transfer. It’s about hedging estimation uncertainty:

r \# Your tool estimates: “Probably 8 minutes locally” \# But estimation
could be off by 3x

Scenario A: Actually takes 3 min → local wins, cloud barely started,
kill it Scenario B: Actually takes 25 min → cloud wins at ~9 min, kill
local

Either way, user gets result faster than pessimistic choice This is
valuable when estimation variance is high - new code, unfamiliar data,
complex dependencies.

Does that reframe it correctly? Speculative execution is about hedging
estimation risk, not recovering local computation progress.

Maybe. I think most people will balk at speculative execution in the
cloud, they’ll see it as waste. I think we have to think about what
makes sense to burst - what are the patterns?

Jan 31

Catalogued practical cloud-burst patterns for research workflows You’re
absolutely right. Speculative execution is clever engineer thinking, not
user thinking. People will hate seeing charges for compute they “didn’t
use.”

Let’s map the actual patterns.

High-Value Burst Patterns 1. Embarrassingly parallel - the obvious
winner

r \# Processing 500 genomic samples results \<- lapply(samples,
function(s) { expensive_analysis(s) \# each takes 20 min })

# Local: 500 × 20min = 167 hours

# Cloud: 500 parallel jobs × 20min = 20 min

# Clear win, no estimation needed

This is what future package already handles well. Your differentiator
would be making AWS the zero-config backend.

2.  Memory overflow

r \# Local machine: 64GB RAM \# Dataset: 120GB

# Won’t fit locally, must use cloud

huge_data \<- read_parquet(“s3://bucket/massive.parquet”) result \<-
analyze(huge_data) Tool detects memory requirements exceed local
capacity → automatic cloud routing.

3.  Long-running single jobs with checkpoints

r \# MCMC sampling - runs for 8 hours mcmc_chain \<- run_mcmc(
iterations = 100000, checkpoint_every = 1000 ) Start on cloud, user can
disconnect, come back later. But this is really “async batch” not
“burst.”

4.  GPU workloads

r \# Deep learning - need GPU model \<- train_model( data, epochs = 100,
device = “gpu” \# triggers cloud routing to g4dn instance ) Local
doesn’t have GPU → cloud is only option.

The Pattern Recognition Problem Users won’t explicitly declare “this is
parallel” or “this needs GPU.” Your tool needs to detect:

r \# User writes normal R code results \<- lapply(big_list,
expensive_function)

# Tool detects:

# - lapply/map pattern → parallelizable

# - Estimated time per item: 15 min

# - List length: 200

# - Local sequential: 50 hours

# - Cloud parallel: 15 min

# → Automatic burst with “Would you like to run this on 200 cloud instances? Cost: \$12, time: 15min vs 50hrs local”

Detection heuristics:

lapply, map, future_map, foreach → parallel candidate apply family on
large objects → maybe parallel Nested loops → might be vectorizable or
parallelizable Package usage (keras, torch) → GPU candidate Object sizes
approaching RAM limits → memory overflow What NOT to Burst 1.
Interactive exploration

r \# User trying things plot(data$x,data$y) summary(data) head(data %\>%
filter(condition)) Latency kills this. Needs immediate feedback.

2.  Tight iteration loops with user in the loop

r \# Shiny apps \# Real-time dashboards \# Interactive debugging 3.
Anything \< 5 minutes total The startup overhead (even 30s Fargate)
isn’t worth it.

4.  Heavy data transfer relative to compute

r \# 50GB dataset \# 2 min computation \# Transfer time: 5 min

# Not worth it

    ## Simplified Decision Tree

Is it lapply/map-style parallel? YES → Count items × estimated time per
item \> 30 min total? → BURST (parallel cloud) \< 30 min total? → LOCAL

NO → Estimated total time? \< 5 min → LOCAL (not worth overhead) 5-30
min → LOCAL (borderline, keep simple) \> 30 min AND (memory OK locally)
→ ASK USER \> 30 min AND (memory tight) → BURST Needs GPU → BURST (or
warn if no GPU code) What This Means for Product Start with the 80/20:

Phase 1: Parallel burst only

r aws_parallel_map(big_list, function(x) { \# self-contained work })
This is clearly valuable, clearly defined, no ambiguity.

Phase 2: Memory overflow detection Automatically route to cloud when
memory requirements exceed local.

Phase 3: Smart suggestions “This looks like it could run in parallel.
Want me to burst it?”

Don’t try to be too clever early. Better to have users explicitly opt-in
to bursting than try to auto-detect everything and get it wrong.

What’s the killer use case for your users (academic research computing)?
Is it the parallel processing of large sample sets?

The killer feature is seamless brain dead simple it just works I agree
with not being clever but there is a tension there

Jan 31

Examined the abstraction paradox between simplicity and intelligent
decision-making That’s the core tension in every great abstraction.

“Just works” requires being clever. But being clever means making
decisions that could be wrong. And when automated decisions are wrong,
users lose trust faster than if they’d made the decision themselves.

The Resolution: Transparent Defaults + Progressive Disclosure Level 0:
Brain-dead simple (what users see first)

r library(awsburst)

# Just works - no configuration

result \<- compute({ lapply(samples, expensive_analysis) })

    Behind the scenes on first run:

⚡ Detected parallel workload (500 items) ⚡ Estimated local time: 167
hours ⚡ Running on cloud: ~20 minutes, est. cost \$8.50 ⚡
\[████████░░\] 80% complete… User didn’t ask for cloud. Tool just did
it. But it told them what it was doing and why.

Level 1: Users start to care about cost

r \# Tool remembers: “User is cost-conscious” \# Shows different
message:

⚡ Detected parallel workload (500 items)  
⚡ Cloud: 20 min (\$8.50) vs Local: 167 hrs (\$0) ⚡ Running on cloud.
\[Set budget limits: aws_burst_config()\] Level 2: Power users want
control

r aws_burst_config( max_cost_per_job = 5, \# hard limit time_value = 50,
\# my hourly rate auto_approve_under = 2 \# don’t ask if \< \$2 )

# Now tool optimizes within constraints

Level 3: Full control when needed

r result \<- compute({…}, strategy = “local”, \# override explain = TRUE
\# show me the decision logic )

    ## Building Trust Through Transparency

    **Never surprise users with cost.** Even in "just works" mode:

First time ever: ⚡ This will use AWS cloud computing (~\$8.50) ⚡ Want
to set a budget limit first? \[yes/no\]

    **Learn from behavior:**
    - User manually kills expensive jobs → lower auto-approval threshold
    - User consistently runs large parallel jobs → increase confidence
    - User hits cost limit → ask about raising it

    **Show the economics:**

Job complete! ✓ Cloud: 18 minutes, \$7.23 (Would have taken 164 hours
locally) Time saved: 163.7 hours Cost per hour saved: \$0.04

    This teaches users the value model. Over time they develop intuition for when cloud makes sense.

    ## The Decision Framework Under the Hood

    You're not being "clever" - you're being **consistent and explainable**:

Rule 1: Parallel workload + \>10 items + \>30min total → Cloud Rule 2:
Memory required \> 80% local RAM → Cloud  
Rule 3: GPU code detected + no local GPU → Cloud Rule 4: Single job
\<10min → Local Rule 5: Cost \> user limit → Ask Not ML, not magic. Just
clear heuristics. And when wrong, users can understand why it decided
that.

Start Small, Learn Fast v0.1: Only parallel lapply/map. One clear
pattern, hard to screw up.

v0.2: Add async batch (long-running single jobs). Still obvious.

v0.3: Add smart defaults for single-job burst based on time estimates.
This is where it gets riskier.

Learn from telemetry (with permission):

How often do users override? What jobs do they kill? Where are estimates
wrong? The Killer Insight from Your Background You have something most
tool builders don’t: economic frameworks that actually work. Your
queueing theory isn’t academic - you’ve proven it with 90+ universities.

The tool’s intelligence isn’t “AI-powered smart scheduling.” It’s:

“This tool embodies 20 years of research computing economics. It knows
when cloud saves you money because the math is fundamental, not
heuristic.”

That’s defensible. That builds trust. Users might not understand
queueing theory, but they understand “this guy ran UCLA’s research
computing for 20 years and now works at AWS - he probably knows when
cloud makes sense.”

Where should it make its first decision? Parallel workloads? Memory
overflow? Something else?

I didn’t say just does it, I said just works I would recommend looking
at coiled as an example for Python

Jan 31

Recalibrated understanding of “just works” versus automatic
decision-making Ah, important distinction. “Just works” ≠ “decides for
you.”

Let me look at Coiled’s model:

What Coiled Gets Right 1. Explicit opt-in, zero configuration

python \# User clearly chooses cloud import coiled

cluster = coiled.Cluster(n_workers=50) client = Client(cluster)

# Now normal Dask code just works on cloud

result = df.groupby(‘key’).mean().compute() 2. Environment sync is
automatic

Detects local packages Builds matching environment on cloud workers User
doesn’t think about Docker, AMIs, etc. 3. Transparent resource
management

User specifies workers/memory Coiled handles instance types, networking,
security groups Bills by second, auto-shutdown 4. Local development
stays local

python \# Develop/test locally with small data client = Client() \#
local cluster

# Scale to cloud when ready - same code

client = Client(coiled.Cluster(n_workers=100)) R Equivalent Pattern r
library(awsburst)

# Explicit: user chooses cloud

cluster \<- aws_cluster(workers = 50)

# Now normal future/parallel code just works

plan(cluster)

results \<- future_map(samples, expensive_analysis) Behind the scenes
(invisible to user):

Spins up Fargate tasks or EC2 instances Syncs R environment (renv
snapshot) Handles S3 data movement Manages authentication Tears down
when done User thinks about: “I want 50 workers” User doesn’t think
about: Instance types, VPCs, Docker, IAM roles, package installation

The “Just Works” Requirements Environment reproducibility:

r \# First time setup - once ever aws_burst_setup()  
\# Captures AWS credentials, creates S3 bucket, ECR repo \# Maybe 2
minutes of one-time config

# Then forever after

cluster \<- aws_cluster(workers = 10) \# Tool automatically: \# -
Snapshots local renv \# - Builds/caches container image \# - Only
rebuilds if packages changed Smart defaults:

r \# Minimal specification cluster \<- aws_cluster(workers = 20) \# Tool
picks: r5.xlarge instances (or Fargate equivalent)

# More control when needed

cluster \<- aws_cluster( workers = 20, memory = “16GB”, \# tool picks
instance family instance = “c5.4xlarge” \# or explicit ) Cost
visibility:

r cluster \<- aws_cluster(workers = 50) \# \> Starting cluster:
~\$3.50/hour, bursting from S3 bucket: my-burst-data \# \> Cluster ready
(52 seconds)

# When done

cluster\$shutdown() \# \> Cluster runtime: 23 minutes \# \> Total cost:
\$1.34 What Makes It “Just Work” for R 1. Package environment sync -
This is the hard part

Coiled has it easier (conda/pip are hermetic) R package installation is
messier Solution: renv + Docker layers + caching 2. Data movement - Your
expertise

CargoShip-powered S3 uploads Intelligent serialization (qs vs arrow vs
fst) Automatic chunking for parallel tasks 3. Authentication - One-time
setup

r aws_burst_setup() \# Walks through: AWS credentials, region, S3 bucket
\# Stores config, never ask again 4. No babysitting

Auto-shutdown after idle Cost alerts if running too long Cleanup failed
jobs The Tension Resolution You’re right - there’s tension between “just
works” and “simple.” Coiled resolves it by:

Making the complex parts invisible (infrastructure) Keeping the
important parts explicit (resource allocation, cost)

For your tool:

User explicitly chooses to use AWS (no surprise bills) Tool handles all
AWS complexity (no learning curve) Transparent about cost and time
(build trust) Does that align better with your vision? The user says “I
want cloud compute” and the tool makes that trivially easy?

It does and I am going to call this “staRburst”

Tell me more about future, what it does, how it works, and why that is
the integration point

Jan 31

Architected explanation of future’s role as staRburst’s integration
foundation future is the backbone of modern parallel computing in R.
Creating a staRburst backend for it means instant compatibility with a
massive ecosystem.

What future Does Core concept: Separate what to compute from where/how
to compute it.

r \# Sequential (normal R) result \<- expensive_function(data)

# Future - same semantics, different execution

f \<- future({ expensive_function(data) }) result \<- value(f) \# blocks
until ready The magic: changing execution model requires zero code
changes, just change the “plan”:

r \# Run locally in background plan(multisession) f \<- future({
slow_work() }) \# … do other stuff … result \<- value(f)

# Run on cluster

plan(cluster, workers = c(“node1”, “node2”, “node3”)) f \<- future({
slow_work() }) \# same code! result \<- value(f) How It Works 1. Future
objects are promises

r f \<- future({ x \<- expensive_computation() x \* 2 }) \# Returns
immediately, computation happens elsewhere 2. Backends (plans) handle
execution

sequential: Run in current R session (default, no parallelism)
multisession: Spawn R workers on local machine multicore: Fork R process
(Unix only) cluster: Run on remote R sessions via SSH future.batchtools:
Submit to HPC schedulers (Slurm, SGE, etc.) 3. Resolving futures

r result \<- value(f) \# blocks until ready 4. Automatic dependency
tracking

r x \<- 10 f \<- future({ x + 5 }) \# `x` is captured and sent to worker
Why This Is Your Integration Point 1. Ecosystem compatibility

Tons of packages build on future:

furrr: future + purrr → parallel map operations r library(furrr)
plan(future_starburst) \# your backend

\# Now this runs on AWS automatically results \<- future_map(samples,
expensive_analysis) future.apply: Parallel lapply, sapply, etc. r
plan(future_starburst) results \<- future_lapply(1:1000, function(i)
simulate(i)) targets: Make-like workflow tool promises: Async
programming for Shiny One integration → works with entire ecosystem

2.  Users already know the API

R users doing parallel work likely already use furrr or future.apply.
staRburst becomes:

r \# Change one line plan(multisession) \# local plan(future_starburst,
workers = 50) \# AWS \# All their existing code just works 3. Clean
separation of concerns

r \# Business logic (user code) analyze \<- function(sample) {
preprocess(sample) %\>% fit_model() %\>% extract_results() }

# Execution strategy (staRburst handles)

plan(future_starburst) results \<- future_map(samples, analyze) User
thinks about what to compute. staRburst handles where.

How future Backends Work Interface to implement:

r \# Simplified - actual implementation more complex plan.starburst \<-
function(workers = 10, …) { \# Setup: create cluster, sync environment
cluster \<- aws_cluster_create(workers)

\# Return plan object structure( list(cluster = cluster, workers =
workers), class = c(“starburst”, “cluster”, “future”) ) }

# Send work to cluster

future_starburst \<- function(expr, envir, …) { \# 1. Capture expression
and dependencies \# 2. Serialize to S3 \# 3. Submit to Fargate/EC2
worker \# 4. Return future object with result location }

# Retrieve result

value.starburst \<- function(future, …) { \# 1. Check if result ready
(poll S3 or use notifications) \# 2. Download result \# 3. Deserialize
and return } The heavy lifting:

Environment capture (what objects does expr need?) Serialization (get
data to workers) Worker management (spin up, monitor, shut down) Result
collection (get data back) staRburst Architecture r library(starburst)

# One-time setup

starburst_setup() \# AWS creds, S3 bucket, etc.

# Create plan

plan(future_starburst, workers = 20, memory = “8GB”, cpu = 4, region =
“us-east-1” )

# Now any future-based code uses AWS

library(furrr) results \<- future_map(big_list, expensive_function)
Behind the scenes:

Environment sync: Snapshot renv.lock, build Docker image, cache in ECR
Cluster creation: Spin up Fargate tasks or EC2 instances Work
distribution: Each future() call → task to worker Data movement:
Serialize deps to S3, workers pull, execute, push results Result
collection: Download results as they complete Cleanup: Auto-shutdown
idle workers Why This Is Better Than Building From Scratch If you built
a custom API:

r \# Your custom thing starburst_map(data, function(x) …) Users need to:

Learn your API Rewrite existing code Limited to your functions With
future backend:

r plan(future_starburst) \# Now ALL future-based code works: \# -
furrr::future_map \# - future.apply::future_lapply \# - targets
pipelines \# - custom future code Users get:

Familiar API Works with existing code Entire ecosystem compatibility The
Technical Challenges 1. Environment reproducibility

Capture local package versions (renv) Build matching Docker image Cache
for reuse (most runs don’t change packages) 2. Data serialization

Large objects: use qs (10x faster than base R) Data frames:
Arrow/Parquet for efficiency Special objects: Handle connections,
pointers gracefully 3. Error handling

Worker crashes → retry or fail gracefully Partial results → save what
completed Cost runaway → kill cluster if budget exceeded 4. Performance

Cold start: 30-60s for Fargate Data transfer: Use your CargoShip
optimizations Task overhead: Batch small tasks to amortize startup
Example Integration r library(starburst) library(furrr)

# Setup cluster

plan(future_starburst, workers = 100)

# Genomics workflow - 10,000 samples

samples \<- list.files(“s3://my-data/samples/”)

results \<- future_map(samples, function(sample_id) { \# Each runs on
separate Fargate task data \<-
read_fastq(paste0(“s3://my-data/samples/”, sample_id)) aligned \<-
align_reads(data) variants \<- call_variants(aligned) return(variants)
}, .options = furrr_options(seed = TRUE))

# Results collected automatically

# Cluster shuts down when done

User experience:

Wrote normal furrr code Added plan(future_starburst) 10,000 samples
processed in ~time of 1 sample Cost: \$47, time: 18 minutes vs 208 hours
locally Does this clarify why future is the right foundation? You’re not
building a parallel computing framework - you’re building an AWS backend
for the existing R parallel computing standard.

Completely, no question Does fargate seem like the best starting point?
Seems coiled keeps it simple as well. Could get more clever with GPU,
EMR etc or remote data or db

Jan 31

Validated start-simple strategy, endorsed Fargate expansion path Fargate
is absolutely the right starting point. Here’s why:

Why Fargate for v1 1. Zero infrastructure management

No AMIs to build/maintain No instance lifecycle (launching, monitoring,
terminating) No capacity planning Just: “run this container with this
much CPU/RAM” 2. Perfect cost model for bursting

Pay per-second from start to stop No warm pools to maintain No minimum
commitments Fits the “spin up, compute, tear down” pattern perfectly 3.
Fast enough

30-60s cold start is acceptable for parallel workloads If you’re running
100 tasks for 20 minutes each, 45s startup is 4% overhead For the
genomics example: 10,000 samples × 18 min each = startup is noise 4.
Simple mental model

r plan(future_starburst, workers = 50, cpu = 4, memory = “8GB” ) That’s
it. User doesn’t think about instance types, spot vs on-demand,
availability zones, etc.

5.  Covers 80% of use cases

CPU-bound parallel work: ✓ Memory up to 120GB: ✓ (covers most R
workloads) No GPU: fine, most R work is CPU Runtime \<hours: ✓ (typical
batch jobs) The Coiled Parallel Coiled started simple too:

Dask workers on managed containers Simple scaling knobs (workers,
memory, CPU) Let users prove value before adding complexity They added
sophisticated features later:

Software environments GPU support Adaptive scaling Cost optimization But
v1 was: “Click button, get Dask cluster.”

staRburst v1 Scope IN scope:

Fargate-based workers (4-16 vCPU, 8-120GB RAM) CPU-bound parallel
workloads future backend integration Automatic environment sync (renv)
S3 data movement Cost tracking and auto-shutdown OUT of scope (for now):

GPU instances 120GB memory jobs

EMR integration Spark clusters Custom VPC/networking Natural Expansion
Path The future backend architecture makes expansion clean:

r \# v1: Fargate only plan(future_starburst, workers = 50)

# v2: Add backend selection

plan(future_starburst, workers = 50, backend = “fargate”) \# default
plan(future_starburst, workers = 10, backend = “ec2-gpu”, instance =
“g4dn.xlarge”)

# v3: Smart backend selection

plan(future_starburst, workers = 50, gpu = TRUE) \# auto-picks EC2 GPU
instances plan(future_starburst, workers = 50, memory = “256GB”) \#
auto-picks EC2 high-mem Under the hood, same architecture:

Container image (from renv) Task submission S3 data movement Result
collection Just swap Fargate ECS tasks for EC2 instances when needed.

When You’d Add EC2 GPU workloads:

r \# User has torch/keras code plan(future_starburst, workers = 4, gpu =
TRUE) \# Backend: Launches g4dn.xlarge instances Memory monsters
(\>120GB):

r \# Genomics with 500GB reference genome plan(future_starburst, workers
= 1, memory = “500GB”) \# Backend: Launches r5.16xlarge Long-running
(\>4 hours) where Spot savings matter:

r \# Overnight simulation plan(future_starburst, workers = 100, spot =
TRUE) \# Backend: Spot instances with interruption handling When You’d
Add EMR/Spark When users need distributed data processing, not just
parallel R:

r \# Billions of rows, distributed joins plan(future_starburst_spark,
workers = 20) \# Behind scenes: EMR cluster, sparklyr integration But
this is different architecture - Spark != R parallelism. Probably a
separate package (starburst.spark?).

MVP Success Criteria v1 is successful if:

Researcher can go from plan(multisession) to plan(future_starburst) in
one line Environment “just works” (renv sync automatic) 100-way
parallelism costs \<\$10 and finishes in minutes vs hours They recommend
it to colleagues You know you need v2 when:

Users ask for GPU support (torch/keras workflows) Memory limits hit
(genomics, large matrix ops) Cost optimization requests (spot instances)
Implementation Priority Week 1-2: Core infrastructure

AWS authentication setup S3 bucket creation ECR repository for Docker
images Basic Fargate task definition Week 3-4: future backend

Implement plan.starburst Task submission to Fargate Basic serialization
(start with qs) Result collection Week 5-6: Environment sync

renv snapshot capture Docker image building ECR caching (only rebuild
when packages change) Week 7-8: Polish

Cost tracking Auto-shutdown Error handling Documentation Week 9-10:
Testing with real workloads

Genomics pipelines Monte Carlo simulations Bootstrap resampling The
Pitch staRburst v1: “Change one line of code, run your parallel R
workload on 100 AWS workers. No Docker, no infrastructure, no hassle.
Works with furrr, future.apply, and the entire future ecosystem.”

Simple. Valuable. Extensible.

Start with Fargate. Prove the model. GPU and fancy stuff comes later
when users demand it.

Sound like the right plan?

Yes, one thing super important, quotas

Jan 31

Examined AWS quota constraints and production-readiness strategies
Absolutely critical. This is where “just works” crashes into AWS
reality.

The Quota Problem Default Fargate vCPU limits (varies by region):

New accounts: Often 40-100 vCPUs total Established accounts: Maybe 1000
vCPUs User tries:

r plan(future_starburst, workers = 100, cpu = 4) \# Needs 400 vCPUs \#
Quota: 100 vCPUs \# Result: 25 tasks launch, 75 fail with cryptic AWS
error User experience: Broken. Confusing. Not “just works.”

staRburst Must Handle This 1. Check quotas before launching

r plan(future_starburst, workers = 100, cpu = 4)

# Behind the scenes:

# - Query Service Quotas API

# - Fargate vCPU quota: 100

# - Requested: 400

# - Action: ???

    **2. Smart responses**

    **Option A: Graceful degradation**

⚠ Requested 100 workers (400 vCPUs) ⚠ Your Fargate quota: 100 vCPUs ⚠
Launching 25 workers instead ⚠ Increase quota:
<https://console.aws.amazon.com/servicequotas/>… ⚠ Continue? \[y/n\]

    **Option B: Incremental scaling**

⚠ Requested 100 workers (400 vCPUs) ⚠ Your Fargate quota: 100 vCPUs  
⚠ Launching in waves: 25 workers at a time ⚠ Tasks will queue and run as
workers complete ✓ Proceeding with wave-based execution

    **Option C: Fail fast with guidance**

✗ Cannot launch 100 workers (400 vCPUs needed) ✗ Current Fargate vCPU
quota: 100 ✗ Options: 1. Request quota increase (usually approved in
24hrs) aws service-quotas request-service-quota-increase  
–service-code fargate –quota-code L-3032A538  
–desired-value 500 2. Reduce workers: plan(future_starburst, workers =
25) 3. Switch to smaller tasks: cpu = 2 (allows 50 workers)
Implementation Strategy Check quotas during setup:

r starburst_setup()

# Checks and reports:

✓ AWS credentials: valid ✓ S3 bucket: created (my-starburst-data) ✓ ECR
repository: created ⚠ Fargate vCPU quota: 100 (you may want to increase
this) Current quota allows ~25 workers with 4 vCPUs each Request
increase: starburst_request_quota_increase() Check quotas before launch:

r plan(future_starburst, workers = 100, cpu = 4)

# Internally:

quota_check \<- get_fargate_quota() needed \<- workers \* cpu if (needed
\> quota_check\$available) { \# Handle gracefully } Helper function:

r starburst_quota_status() \# \> Fargate vCPU quota: 100 / 100 used \#
\> Recommended: Request increase to 500 \# \> \# \>
starburst_request_quota_increase(vcpus = 500) Key Quotas to Track
Fargate:

vCPU limit (per region) Tasks per cluster Usually the bottleneck EC2
(for future GPU/spot):

Instance type limits (especially GPU) Spot instance limits On-demand
vCPU limits S3:

Request rate (5500 PUT/s per prefix) Usually not a problem but good to
monitor ECR:

Image storage (10 TB default) Pull rate limits Wave-Based Execution
(Best UX) r plan(future_starburst, workers = 100, cpu = 4)

# If quota only allows 25 at a time:

✓ Starting cluster: 25 workers (wave 1 of 4) ⚡ \[Wave 1: ████████████\]
100% complete (127 tasks done) ⚡ \[Wave 2: ████████░░░░\] 67% complete
(85 tasks done) … This way:

User gets all 100 workers worth of work done Just takes longer
(sequential waves vs parallel) No manual intervention needed Transparent
about what’s happening Quota Increase Automation r
starburst_request_quota_increase( vcpus = 500, justification = “Running
parallel genomics analysis” )

# Behind scenes:

# - Calls Service Quotas API

# - Creates increase request

# - AWS usually approves in 1-24 hours for reasonable requests

# - Sends email to user when approved

Pre-emptive guidance:

r starburst_setup()

# During setup, if quota is low:

⚠ Your Fargate quota (100 vCPUs) is low for parallel workloads ⚠ We
recommend requesting an increase to 500 vCPUs ⚠ This usually takes 24
hours to approve ⚠ Request now? \[y/n\] Why This Matters Without quota
handling:

User: “This doesn’t work, got weird errors” Reality: Hit quota, partial
failure, confusing Outcome: Abandoned tool, bad review With quota
handling:

User: “Asked for 100 workers, quota only allowed 25, tool told me how to
fix it” Reality: Transparent, helpful, actionable Outcome: User requests
quota increase, comes back, succeeds Check During CI/Testing r \# In
test suite test_that(“quota checks work”, { \# Mock quota API quota \<-
100 plan \<- plan_starburst(workers = 50, cpu = 4) \# needs 200

expect_warning(“quota”) expect_equal(plan\$actual_workers, 25) \#
graceful degradation }) Documentation Critical Section README.md:

markdown \### AWS Quotas

staRburst requires sufficient AWS Fargate vCPU quota.

**Check your quota:** - Visit AWS Console \> Service Quotas \> Fargate -
Or run:
[`starburst_quota_status()`](https://starburst.ing/reference/starburst_quota_status.md)

**Typical quotas:** - New accounts: 100 vCPUs (allows ~25 workers) -
After increase: 500-1000 vCPUs (allows 100+ workers)

**Request increase:** 1. Automatic:
`starburst_request_quota_increase(vcpus = 500)` 2. Manual: \[AWS Console
instructions\]

Approval usually takes 1-24 hours. You know this pain intimately from
AWS work - users hitting quotas is the \#1 support issue for any AWS
tool. Handle it proactively and staRburst is 10x better than
alternatives.

What’s your experience with quota issues at AWS? Any patterns you’ve
seen for handling this gracefully?

Wave based for sure plus ask to make quota increase request for user

Jan 31

Validated wave-based execution strategy and proactive quota assistance
approach Perfect. That’s the right UX. Let me sketch the flow:

Ideal User Experience First-time user, low quota:

r library(starburst)

plan(future_starburst, workers = 100, cpu = 4)

⚡ Checking Fargate capacity… ⚠ Requested: 100 workers (400 vCPUs) ⚠
Current quota: 100 vCPUs (allows 25 workers max)

📋 Execution plan: • Running in 4 waves of 25 workers each • Wave 1:
starts immediately • Waves 2-4: start as workers complete • Estimated
total time: ~same as 100 parallel + 3x startup overhead

💡 Quota increase recommended: Request 500 vCPU quota? (usually approved
in 1-24 hours) \[y/n\]: y

✓ Quota increase requested (Case ID: 12345678) ✓ You’ll receive email
when approved ✓ Future runs will use full parallelism

⚡ Starting wave 1 (25 workers)… User just says yes once, problem solved
forever.

Implementation Quota check with automatic fallback:

r plan.starburst \<- function(workers = 10, cpu = 4, memory = “8GB”, …)
{

\# Check quota quota_info \<- check_fargate_quota() vcpus_needed \<-
workers \* cpu vcpus_available \<- quota_info\$limit

if (vcpus_needed \> vcpus_available) { \# Calculate wave-based execution
workers_per_wave \<- floor(vcpus_available / cpu) num_waves \<-
ceiling(workers / workers_per_wave)

``` R
# Inform user
cat_info(sprintf(
  "⚠ Requested: %d workers (%d vCPUs)\n⚠ Current quota: %d vCPUs (allows %d workers max)\n",
  workers, vcpus_needed, vcpus_available, workers_per_wave
))

cat_info(sprintf(
  "\n📋 Execution plan:\n   • Running in %d waves of %d workers each\n",
  num_waves, workers_per_wave
))

# Offer quota increase
if (!quota_info$increase_pending && interactive()) {
  recommended_quota <- suggest_quota(vcpus_needed)
  
  cat_info(sprintf(
    "\n💡 Quota increase recommended:\n   Request %d vCPU quota? (usually approved in 1-24 hours)\n",
    recommended_quota
  ))
  
  response <- readline("   [y/n]: ")
  if (tolower(response) == "y") {
    case_id <- request_quota_increase(
      quota_code = "L-3032A538",  # Fargate vCPU
      desired_value = recommended_quota,
      reason = sprintf("Parallel R computing with %d workers", workers)
    )
    cat_success(sprintf("✓ Quota increase requested (Case ID: %s)\n", case_id))
    cat_success("✓ You'll receive email when approved\n")
  }
}

# Create wave-based plan
plan <- list(
  workers = workers,
  workers_per_wave = workers_per_wave,
  num_waves = num_waves,
  cpu = cpu,
  memory = memory,
  quota_limited = TRUE
)
```

} else { \# Sufficient quota plan \<- list( workers = workers,
workers_per_wave = workers, num_waves = 1, cpu = cpu, memory = memory,
quota_limited = FALSE ) }

structure(plan, class = c(“starburst”, “cluster”, “future”)) } Wave
Execution When tasks are submitted:

r \# User code results \<- future_map(samples, expensive_analysis)

# Behind the scenes

submit_tasks_with_waves \<- function(tasks, plan) { if
(plan\$quota_limited) { \# Queue-based execution task_queue \<- tasks
results \<- list()

``` R
for (wave in 1:plan$num_waves) {
  cat_info(sprintf("⚡ Starting wave %d of %d (%d workers)...\n", 
                  wave, plan$num_waves, plan$workers_per_wave))
  
  # Launch workers for this wave
  wave_tasks <- head(task_queue, plan$workers_per_wave)
  task_queue <- tail(task_queue, -plan$workers_per_wave)
  
  # Submit to Fargate
  wave_futures <- lapply(wave_tasks, submit_to_fargate)
  
  # Wait for wave to complete
  wave_results <- lapply(wave_futures, value)
  results <- c(results, wave_results)
  
  # Progress
  cat_success(sprintf("✓ Wave %d complete (%d/%d tasks done)\n",
                     wave, length(results), length(tasks)))
}
```

} else { \# Normal parallel execution \# All tasks at once } } Smart
Quota Suggestions r suggest_quota \<- function(needed_vcpus) { \# Round
up to reasonable increments \# AWS likes: 100, 200, 500, 1000, 2000,
5000

if (needed_vcpus \<= 200) return(200) if (needed_vcpus \<= 500)
return(500) if (needed_vcpus \<= 1000) return(1000) if (needed_vcpus \<=
2000) return(2000) return(5000) } Reasoning: Ask for more than you need
now, so you don’t hit the limit again soon. If they need 400, request
500.

Non-Interactive Mode For scripts/automation:

r \# In automated script plan(future_starburst, workers = 100,
auto_quota_request = TRUE) \# Don’t prompt, just request

# Or

options(starburst.auto_quota = TRUE) plan(future_starburst, workers =
100) Quota Increase Request Function r request_quota_increase \<-
function(quota_code, desired_value, reason = ““) { tryCatch({ \# AWS
Service Quotas API response \<-
service_quotas_client\$request_service_quota_increase( ServiceCode
=”fargate”, QuotaCode = quota_code, DesiredValue = desired_value )

``` R
# Store case ID for tracking
case_id <- response$RequestedQuota$CaseId

# Save to local config
save_quota_request(case_id, desired_value)

return(case_id)
```

}, error = function(e) { cat_error(“Failed to request quota increase”)
cat_error(“Please request manually:
[https://console.aws.amazon.com/servicequotas/\n](https://console.aws.amazon.com/servicequotas/%5Cn)”)
return(NULL) }) } Check Pending Requests r check_fargate_quota \<-
function() { \# Current quota quota_response \<-
service_quotas_client\$get_service_quota( ServiceCode = “fargate”,
QuotaCode = “L-3032A538” )

current_limit \<- quota_response$Quota$Value

\# Check for pending increases pending_response \<-
service_quotas_client\$list_requested_service_quota_change_history_by_quota(
ServiceCode = “fargate”, QuotaCode = “L-3032A538”, Status = “PENDING” )

has_pending \<- length(pending_response\$RequestedQuotas) \> 0

list( limit = current_limit, increase_pending = has_pending ) } Setup
Wizard Enhancement r starburst_setup \<- function() {
cat_header(“staRburst Setup”)

\# … AWS credentials, S3, ECR setup …

\# Check quota proactively quota_info \<- check_fargate_quota()

cat_info(sprintf(“📊 Current Fargate vCPU quota: %d”,
quota_info\$limit))

if (quota_info\$limit \< 500) { cat_info("\n💡 For typical parallel
workloads, we recommend 500+ vCPUs\n") cat_info(sprintf(" Your current
quota (%d) allows ~%d workers with 4 vCPUs each\n", quota_info\$limit,
floor(quota_info\$limit / 4)))

``` R
if (!quota_info$increase_pending && interactive()) {
  response <- readline("\nRequest quota increase to 500 vCPUs now? [y/n]: ")
  if (tolower(response) == "y") {
    request_quota_increase("L-3032A538", 500, "staRburst parallel computing")
    cat_success("✓ Quota increase requested\n")
  }
}
```

} else { cat_success(sprintf(“✓ Quota is sufficient (%d vCPUs)”,
quota_info\$limit)) } } User-Facing Documentation README:

markdown \### Scaling Beyond Quota Limits

staRburst automatically handles AWS quota limitations:

**Wave-based execution:** - If you request 100 workers but quota allows
25 - staRburst runs in 4 waves of 25 workers - All work completes, just
takes slightly longer - No manual intervention needed

**Automatic quota increases:** - staRburst will offer to request quota
increases - Usually approved within 1-24 hours - Future runs will use
full parallelism

**Manual quota check:**

``` r
starburst_quota_status()
```

This handles the single biggest UX failure mode gracefully and
proactively. Users get their work done immediately (wave-based) AND the
problem gets solved permanently (quota increase).

Sound good?

Create a set of artifacts for this project

Jan 31

Architected comprehensive R package artifacts for AWS computation
bursting I’ll create a comprehensive set of artifacts for the staRburst
project. Let me build out the key documentation and implementation
files.

Assembled comprehensive artifacts for project delivery I’ve created a
comprehensive set of artifacts for the staRburst project. Here’s what
you have:

Core Documentation README.md - User-facing documentation with:

Quick start guide Installation instructions Usage examples with furrr,
future.apply Cost management features Quota handling explanation
Comparison to alternatives ARCHITECTURE.md - Technical design document
covering:

System architecture diagrams Component deep dive (client library,
environment sync, task execution) Quota management strategy Data flow
optimization Security model Performance benchmarks ROADMAP.md -
Implementation plan with:

10 development phases (MVP through production-ready) 20-week timeline to
v1.0 Post-v1.0 features (GPU, Spot, EMR) Risk mitigation strategies
Success metrics Package Structure DESCRIPTION - R package metadata with
dependencies:

future, paws (AWS SDK), qs, renv, arrow Proper versioning and license
info Core Implementation R/plan-starburst.R - The heart of the future
backend:

plan.starburst() - Sets up execution plan with quota checking
future_starburst() - Creates futures on AWS value.starburst_future() -
Retrieves results Wave-based execution logic Cost estimation R/setup.R -
One-time configuration:

starburst_setup() - Interactive setup wizard AWS resource creation (S3,
ECR, ECS, VPC) Configuration persistence starburst_config() - User
preferences R/quota.R - Quota management:

check_fargate_quota() - Query current limits
starburst_request_quota_increase() - Automated requests
starburst_quota_status() - User-friendly status Wave execution
calculations User Guide vignettes/getting-started.Rmd - Complete
tutorial with:

Real-world examples (Monte Carlo, bootstrap, genomics) Data handling
patterns Cost management Troubleshooting Best practices Key Design
Decisions Captured Fargate as starting point - Simplicity over EC2
complexity Wave-based quota handling - Graceful degradation, automatic
quota requests future backend integration - Instant ecosystem
compatibility Cost transparency - Always show estimates and actuals renv
for environment sync - Reproducible, cacheable The project structure is
ready for development. You can start with Phase 1 (MVP) and build
iteratively. The architecture supports your vision of “seamless,
brain-dead simple, just works” while handling the real-world complexity
of quotas and AWS infrastructure.

Readme Document · MD Architecture Document · MD Roadmap Document · MD
DESCRIPTION

Plan starburst Code · R Setup Code · R Quota Code · R Getting started
RMD

Claude is AI and can make mistakes. Please double-check responses.
