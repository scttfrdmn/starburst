#!/bin/bash
# AWS Integration Test Runner
#
# This script runs integration tests against real AWS infrastructure.
# Requires AWS credentials to be configured (via AWS_PROFILE or default credentials).
#
# Usage:
#   ./run-aws-tests.sh [test-suite]
#
# Test suites:
#   all                - Run all AWS integration tests (default)
#   quick              - Quick smoke tests only
#   detached-sessions  - Detached session tests
#   integration-examples - Example script integration tests
#   ec2                - EC2 integration tests
#   cleanup            - Session cleanup tests
#   dangerous          - Includes expensive/slow manual tests

set -e

TEST_SUITE="${1:-all}"
AWS_PROFILE="${AWS_PROFILE:-aws}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}staRburst AWS Integration Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Verify AWS credentials
echo -e "${YELLOW}[1/6] Verifying AWS credentials...${NC}"
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: AWS credentials not available or invalid${NC}"
    echo "Please configure AWS credentials:"
    echo "  export AWS_PROFILE=your-profile"
    echo "  OR"
    echo "  aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text)
echo -e "${GREEN}✓ AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✓ AWS User: $AWS_USER${NC}"
echo ""

# Verify R and package
echo -e "${YELLOW}[2/6] Verifying R installation...${NC}"
if ! command -v Rscript &> /dev/null; then
    echo -e "${RED}ERROR: Rscript not found. Please install R.${NC}"
    exit 1
fi
R_VERSION=$(Rscript -e "cat(paste(R.version\$major, R.version\$minor, sep='.'))")
echo -e "${GREEN}✓ R version: $R_VERSION${NC}"
echo ""

# Load package
echo -e "${YELLOW}[3/6] Loading starburst package...${NC}"
Rscript -e "devtools::load_all(quiet=TRUE); cat('✓ Package loaded\n')"
echo ""

# Verify staRburst AWS configuration
echo -e "${YELLOW}[4/6] Verifying staRburst AWS setup...${NC}"
Rscript -e "
devtools::load_all(quiet=TRUE)
config <- starburst_config()
cat(sprintf('✓ AWS Account ID: %s\n', config\$aws_account_id))
cat(sprintf('✓ Region: %s\n', config\$region))
cat(sprintf('✓ S3 Bucket: %s\n', config\$bucket))
cat(sprintf('✓ ECS Cluster: %s\n', config\$cluster %||% 'starburst-cluster'))

# Test S3 access
s3 <- paws.storage::s3(config = list(region = config\$region))
tryCatch({
  s3\$head_bucket(Bucket = config\$bucket)
  cat('✓ S3 bucket accessible\n')
}, error = function(e) {
  cat('✗ S3 bucket not accessible:', e\$message, '\n')
  stop('S3 access failed')
})

# Test ECR access
ecr <- paws.compute::ecr(config = list(region = config\$region))
tryCatch({
  repos <- ecr\$describe_repositories()
  cat('✓ ECR access OK\n')
}, error = function(e) {
  cat('⚠ ECR access limited (may need setup)\n')
})
"
echo ""

# Run tests based on suite
echo -e "${YELLOW}[5/6] Running test suite: $TEST_SUITE${NC}"
echo ""

run_test_file() {
    local test_file=$1
    local test_name=$2
    local extra_env=$3

    echo -e "${BLUE}Running $test_name...${NC}"

    if eval "$extra_env Rscript -e \"
        devtools::load_all(quiet=TRUE)
        results <- testthat::test_file('$test_file', reporter='summary')
        failed <- sum(sapply(results, function(r) r\\\$failed %||% 0))
        if (failed > 0) quit(status=1)
    \""; then
        echo -e "${GREEN}✓ $test_name: PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ $test_name: FAILED${NC}"
        return 1
    fi
}

TEST_FAILED=0

case "$TEST_SUITE" in
    quick)
        echo -e "${BLUE}Running quick smoke tests only${NC}"
        Rscript -e "
            devtools::load_all()
            config <- starburst_config()
            cat('Basic AWS connectivity: OK\n')
        " || TEST_FAILED=1
        ;;

    detached-sessions)
        run_test_file "tests/testthat/test-detached-sessions.R" "Detached Sessions" "" || TEST_FAILED=1
        ;;

    integration-examples)
        run_test_file "tests/testthat/test-integration-examples.R" "Integration Examples" "RUN_INTEGRATION_TESTS=TRUE" || TEST_FAILED=1
        ;;

    ec2)
        run_test_file "tests/testthat/test-ec2-integration.R" "EC2 Integration" "" || TEST_FAILED=1
        ;;

    cleanup)
        run_test_file "tests/testthat/test-cleanup.R" "Cleanup" "" || TEST_FAILED=1
        ;;

    dangerous)
        echo -e "${RED}WARNING: This will run expensive/slow tests that may take 30+ minutes${NC}"
        echo "Press Ctrl+C within 5 seconds to cancel..."
        sleep 5

        run_test_file "tests/testthat/test-detached-sessions.R" "Detached Sessions" "" || TEST_FAILED=1
        run_test_file "tests/testthat/test-integration-examples.R" "Integration Examples" "RUN_INTEGRATION_TESTS=TRUE" || TEST_FAILED=1
        run_test_file "tests/testthat/test-ec2-e2e.R" "EC2 End-to-End" "" || TEST_FAILED=1
        run_test_file "tests/testthat/test-cleanup.R" "Cleanup" "" || TEST_FAILED=1
        ;;

    all)
        run_test_file "tests/testthat/test-detached-sessions.R" "Detached Sessions" "" || TEST_FAILED=1
        run_test_file "tests/testthat/test-integration-examples.R" "Integration Examples" "RUN_INTEGRATION_TESTS=TRUE" || TEST_FAILED=1
        run_test_file "tests/testthat/test-ec2-integration.R" "EC2 Integration" "" || TEST_FAILED=1
        run_test_file "tests/testthat/test-cleanup.R" "Cleanup" "" || TEST_FAILED=1
        ;;

    *)
        echo -e "${RED}ERROR: Unknown test suite: $TEST_SUITE${NC}"
        echo "Valid suites: all, quick, detached-sessions, integration-examples, ec2, cleanup, dangerous"
        exit 1
        ;;
esac

echo ""

# Cleanup
echo -e "${YELLOW}[6/6] Cleaning up test resources...${NC}"
Rscript -e "
tryCatch({
    devtools::load_all(quiet=TRUE)

    # List sessions
    sessions <- tryCatch(starburst_list_sessions(), error = function(e) list())

    if (length(sessions) > 0) {
        cat('Found', length(sessions), 'sessions to clean up\n')
        for (session_id in names(sessions)) {
            cat('  Cleaning:', session_id, '\n')
            tryCatch({
                session <- starburst_session_attach(session_id)
                session\$cleanup(force = TRUE)
            }, error = function(e) {
                cat('    Warning:', e\$message, '\n')
            })
        }
    } else {
        cat('No sessions to clean up\n')
    }
}, error = function(e) {
    cat('Cleanup warning (non-fatal):', e\$message, '\n')
})
" || echo -e "${YELLOW}⚠ Cleanup had warnings (non-fatal)${NC}"

echo ""
echo -e "${BLUE}========================================${NC}"

if [ $TEST_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo -e "${BLUE}========================================${NC}"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo -e "${BLUE}========================================${NC}"
    exit 1
fi
