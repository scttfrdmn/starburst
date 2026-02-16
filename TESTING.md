# staRburst Testing Guide

## Overview

staRburst has three tiers of testing:

1.  **Unit Tests** - Fast, no external dependencies, run on every commit
2.  **Integration Tests** - Require AWS, test real infrastructure, run
    on-demand or weekly
3.  **Manual Tests** - Expensive/slow tests for capacity limits, run
    manually before releases

## Test Statistics

- **Total Tests**: 236 tests
- **Unit Tests**: 202 tests (always run)
- **Integration Tests**: 34 tests (require AWS)

## Running Tests Locally

### Unit Tests (No AWS Required)

``` bash
# Run all unit tests
Rscript -e "devtools::test()"

# Expected: [ FAIL 0 | WARN 0 | SKIP 34 | PASS 202 ]
```

### Integration Tests (AWS Required)

``` bash
# Quick smoke test
./run-aws-tests.sh quick

# Run all integration tests
./run-aws-tests.sh all

# Run specific test suite
./run-aws-tests.sh detached-sessions
./run-aws-tests.sh integration-examples
./run-aws-tests.sh ec2
./run-aws-tests.sh cleanup

# Run expensive/slow tests (30+ minutes)
./run-aws-tests.sh dangerous
```

**Prerequisites:** - AWS credentials configured (`AWS_PROFILE=aws` or
default credentials) - staRburst AWS infrastructure deployed (S3 bucket,
ECR repo, ECS cluster) - Sufficient AWS quotas for Fargate tasks

### Individual Test Files

``` bash
# Detached sessions
Rscript -e "devtools::load_all(); testthat::test_file('tests/testthat/test-detached-sessions.R')"

# Integration examples
RUN_INTEGRATION_TESTS=TRUE Rscript -e "devtools::load_all(); testthat::test_file('tests/testthat/test-integration-examples.R')"

# EC2 integration
Rscript -e "devtools::load_all(); testthat::test_file('tests/testthat/test-ec2-integration.R')"

# Cleanup tests
Rscript -e "devtools::load_all(); testthat::test_file('tests/testthat/test-cleanup.R')"
```

## GitHub Actions CI/CD

### Unit Tests (R CMD check)

Runs automatically on every push and pull request: -
`.github/workflows/R-CMD-check.yaml` - Tests all 202 unit tests - No AWS
credentials required - Fast (~5 minutes)

### AWS Integration Tests

Manual trigger or weekly scheduled run: -
`.github/workflows/aws-integration-tests.yml` - Tests all 34 integration
tests against real AWS - Requires AWS credentials (OIDC role) - Runs
Monday 8am UTC + manual dispatch - Duration: ~30-45 minutes

**To trigger manually:** 1. Go to Actions tab in GitHub 2. Select “AWS
Integration Tests” 3. Click “Run workflow” 4. Choose test suite: `all`,
`quick`, `detached-sessions`, `integration-examples`, `ec2`, or
`cleanup`

## Test Categories

### Unit Tests (202 tests)

**Always run, no AWS required:**

- `test-future-backend.R` - Future API compliance
- `test-plan-starburst.R` - Plan object creation (mocked)
- `test-task-storage.R` - Task registry
- `test-docker.R` - Docker image building (mocked)
- `test-utils.R` - Utility functions
- `test-security.R` - Input validation, command injection prevention
- `test-waves.R` - Wave queue logic
- `test-integration-logic.R` - Environment setup logic (mocked)
- `test-task-def.R` - ECS task definition (mocked)

### Integration Tests (34 tests)

**Require AWS credentials and infrastructure:**

#### Detached Sessions (14 tests)

`test-detached-sessions.R` - Tests session lifecycle: - Session
creation, state management - Task submission and collection - Session
attach/detach - Session listing - Multi-task workflows

#### Integration Examples (9 tests)

`test-integration-examples.R` - End-to-end example validation: - Monte
Carlo portfolio simulation (local + AWS) - Bootstrap confidence
intervals (local + AWS) - Parallel data processing (local + AWS) -
Hyperparameter grid search (local + AWS) - Results consistency
verification

#### EC2 Integration (7 tests)

`test-ec2-e2e.R` + `test-ec2-integration.R`: - EC2 capacity providers -
Spot instance configuration - Multi-platform (X86_64 + ARM64) images -
ECR image management - Pool lifecycle

#### Cleanup (6 tests)

`test-cleanup.R` - Resource cleanup: - Worker termination
(`stop_workers`) - S3 file deletion (`force=TRUE`) - Task ARN tracking -
Session-specific cleanup - Manifest updates

#### ECR Lifecycle (3 tests)

`test-ecr-cleanup.R`: - Lifecycle policy creation - Image age
validation - Manual cleanup

### Manual Tests (excluded from `all`)

**Expensive or slow, run manually:**

- Multi-platform image builds (~20 minutes)
- Warm pool timeout testing (~5+ minutes)
- High worker count tests (quota dependent)

## Test Infrastructure Requirements

### AWS Resources

Integration tests require:

1.  **S3 Bucket** - For task/result storage
    - Must be accessible from ECS tasks
    - Should have lifecycle policies for cleanup
2.  **ECR Repository** - `starburst-worker`
    - Stores Docker images
    - Should have lifecycle policy (retain last 10 images)
3.  **ECS Cluster** - Default: `starburst-cluster`
    - Fargate capacity provider
    - Optional: EC2 capacity provider for EC2 tests
4.  **IAM Roles**
    - ECS Task Execution Role (ECR, CloudWatch Logs)
    - ECS Task Role (S3, ECR, ECS)
5.  **VPC Configuration** (optional)
    - Private subnets for workers
    - VPC endpoints for S3, ECR, ECS (recommended)

### AWS Quotas

Minimum quotas needed: - **Fargate vCPUs**: 16 (for 4 workers × 4
vCPUs) - **Fargate Tasks**: 10 concurrent - **ECR Storage**: 5 GB (for
image storage)

Recommended for full testing: - **Fargate vCPUs**: 64+ (for parallel
execution) - **Fargate Tasks**: 20+ concurrent

### GitHub Actions Setup

For CI/CD, configure GitHub repository secrets:

1.  **AWS_ROLE_ARN** - OIDC role ARN for GitHub Actions

        arn:aws:iam::ACCOUNT_ID:role/GitHubActionsStarburstTesting

2.  **OIDC Trust Policy** - Allow GitHub Actions

    ``` json
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:sub": "repo:scttfrdmn/starburst:ref:refs/heads/main",
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          }
        }
      }]
    }
    ```

## Test Maintenance

### Adding New Tests

1.  **Unit tests** - Add to appropriate `tests/testthat/test-*.R` file

    - Use mocks for AWS services
    - Should run in \<1 second
    - No external dependencies

2.  **Integration tests** - Add skip guards:

    ``` r
    test_that("my AWS test", {
      skip_on_cran()
      skip_if(Sys.getenv("AWS_PROFILE") == "", "AWS credentials not available")

      # Test code using real AWS
    })
    ```

3.  **Manual tests** - Add explicit skip:

    ``` r
    test_that("expensive operation", {
      skip("Manual test - expensive/slow")

      # Test code
    })
    ```

### Updating Integration Tests

When modifying AWS functionality: 1. Update relevant unit tests (with
mocks) 2. Update integration tests (real AWS) 3. Run locally:
`./run-aws-tests.sh all` 4. Trigger GitHub Actions workflow 5. Monitor
for failures in weekly scheduled runs

### Test Debugging

**Local debugging:**

``` r
# Load package
devtools::load_all()

# Set breakpoints
debugonce(starburst_session)

# Run single test
testthat::test_file("tests/testthat/test-detached-sessions.R")
```

**AWS debugging:**

``` bash
# Check CloudWatch logs
aws logs tail /aws/ecs/starburst-worker --follow

# Check ECS tasks
aws ecs list-tasks --cluster starburst-cluster

# Check S3 files
aws s3 ls s3://your-bucket/sessions/

# Check session status
Rscript -e "devtools::load_all(); starburst_list_sessions()"
```

## Cleanup After Failed Tests

``` bash
# Manual cleanup script
./run-aws-tests.sh quick  # Runs cleanup in [6/6] step

# Or cleanup manually in R:
Rscript -e "
  devtools::load_all()

  # Clean up sessions
  sessions <- starburst_list_sessions()
  for (id in names(sessions)) {
    session <- starburst_session_attach(id)
    session\$cleanup(force = TRUE)
  }

  # Stop orphaned tasks
  config <- starburst_config()
  ecs <- paws.compute::ecs(config = list(region = config\$region))
  tasks <- ecs\$list_tasks(cluster = config\$cluster)
  for (task in tasks\$taskArns) {
    ecs\$stop_task(cluster = config\$cluster, task = task, reason = 'Manual cleanup')
  }
"
```

## Cost Considerations

### Unit Tests

- **Cost**: \$0 (no AWS resources)
- **Duration**: ~2-3 minutes

### Integration Tests

- **Compute**: ~\$0.10-0.50 per run
  - Fargate tasks: \$0.04048/vCPU-hour × 4 vCPUs × 0.1 hours ≈ \$0.016
    per test
  - Multiple tests, parallel execution
- **Storage**: Negligible (\<\$0.01/month)
- **Data Transfer**: Minimal (\<\$0.01/run)

**Estimated monthly cost** (with weekly runs): - Weekly scheduled: 4
runs/month × \$0.30 = **\$1.20/month** - Manual runs: Variable,
typically **\$0-2/month** - **Total: ~\$2-3/month**

### Manual/Expensive Tests

- Multi-platform builds: \$0.20-0.50 per build
- High worker count: \$2-10 per run (depending on duration)

## Monitoring Test Health

### GitHub Actions Badge

Add to README.md:

``` markdown
[![AWS Integration Tests](https://github.com/scttfrdmn/starburst/actions/workflows/aws-integration-tests.yml/badge.svg)](https://github.com/scttfrdmn/starburst/actions/workflows/aws-integration-tests.yml)
```

### Test Metrics

Monitor over time: - Pass/fail rate - Duration trends - AWS cost
trends - Flaky test identification

## Troubleshooting

### “AWS credentials not available”

``` bash
# Check credentials
aws sts get-caller-identity --profile aws

# Configure if needed
aws configure --profile aws
export AWS_PROFILE=aws
```

### “S3 bucket not accessible”

``` bash
# Check bucket exists and you have access
aws s3 ls s3://your-starburst-bucket/

# Check starburst config
Rscript -e "devtools::load_all(); starburst_config()"
```

### “Insufficient Fargate vCPU quota”

``` bash
# Check current quota
aws service-quotas get-service-quota \
  --service-code fargate \
  --quota-code L-3032A538

# Request increase
aws service-quotas request-service-quota-increase \
  --service-code fargate \
  --quota-code L-3032A538 \
  --desired-value 64
```

### Tests hang indefinitely

- Workers may be stuck polling for tasks
- Check CloudWatch logs:
  `aws logs tail /aws/ecs/starburst-worker --follow`
- Stop hanging tasks manually
- Increase test timeouts if legitimate slow operations

## Best Practices

1.  **Run unit tests frequently** - Every change, pre-commit
2.  **Run integration tests before releases** - Validate AWS
    functionality
3.  **Monitor weekly scheduled runs** - Catch infrastructure drift
4.  **Clean up after tests** - Prevent orphaned resources
5.  **Update tests with code changes** - Keep tests in sync
6.  **Use mocks in unit tests** - Fast, no AWS costs
7.  **Skip expensive tests by default** - Require explicit opt-in
8.  **Document test requirements** - Help others run tests

## Questions?

- Check test output for specific errors
- Review CloudWatch logs for worker failures
- Ensure AWS infrastructure is properly configured
- Verify quotas are sufficient
- Open an issue if tests consistently fail
