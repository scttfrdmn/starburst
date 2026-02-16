# staRburst Implementation Roadmap

## Overview

staRburst is a future backend for seamless AWS cloud bursting of
parallel R workloads. This document outlines the development roadmap
from MVP to production-ready package.

## Development Phases

### Phase 1: MVP (Weeks 1-4)

**Goal**: Prove the concept with minimal viable functionality

**Core Features**: - \[x\] Basic future backend interface - \[ \]
Single-worker Fargate execution - \[ \] Simple serialization (base R
serialize) - \[ \] Manual environment specification - \[ \] Basic S3
data transfer - \[ \] Hardcoded AWS resources (no setup wizard)

**Deliverable**: Can execute `future({ expr })` on single Fargate
container

**Testing**: - Unit tests for serialization - Manual integration test
with AWS account - Simple benchmark vs local execution

### Phase 2: Environment Sync (Weeks 5-6)

**Goal**: Automatic package environment matching

**Features**: - \[ \] renv snapshot capture - \[ \] Docker image
building with renv restore - \[ \] ECR image caching (based on renv.lock
hash) - \[ \] Image build progress reporting

**Deliverable**: Workers automatically have same packages as local

**Testing**: - Test with various package combinations - Verify cache
hits/misses - Measure build times

### Phase 3: Parallel Execution (Weeks 7-8)

**Goal**: Support multiple concurrent workers

**Features**: - \[ \] Multi-worker task submission - \[ \] Parallel
result collection - \[ \] Progress reporting - \[ \] Error handling for
partial failures

**Deliverable**: `future_map()` works with multiple workers

**Testing**: - 10, 50, 100 worker tests - Failure injection tests -
Performance benchmarks

### Phase 4: Quota Management (Weeks 9-10)

**Goal**: Handle AWS quota limits gracefully

**Features**: - \[ \] Quota checking via Service Quotas API - \[ \]
Wave-based execution when quota-limited - \[ \] Automatic quota increase
requests - \[ \] Quota status reporting

**Deliverable**: Smooth UX even when hitting quota limits

**Testing**: - Mock quota limitations - Test wave execution logic -
Verify quota increase requests

### Phase 5: Setup & Configuration (Weeks 11-12)

**Goal**: One-time setup wizard and user configuration

**Features**: - \[ \]
[`starburst_setup()`](https://scttfrdmn.github.io/starburst/reference/starburst_setup.md)
wizard - \[ \] S3 bucket creation - \[ \] ECR repository creation - \[
\] ECS cluster creation - \[ \] VPC resource setup (subnets, security
groups) - \[ \] Configuration persistence - \[ \]
[`starburst_config()`](https://scttfrdmn.github.io/starburst/reference/starburst_config.md)
for user preferences

**Deliverable**: Zero-config user experience after one-time setup

**Testing**: - Setup from scratch - Setup with existing resources -
Config validation

### Phase 6: Cost Tracking (Week 13)

**Goal**: Transparent cost estimation and reporting

**Features**: - \[ \] Pre-execution cost estimation - \[ \] Real-time
cost tracking during execution - \[ \] Post-execution cost reporting -
\[ \] Cost limit enforcement - \[ \] Cost alerts

**Deliverable**: Users always know how much they’re spending

**Testing**: - Validate cost calculations against AWS bills - Test cost
limit enforcement

### Phase 7: Optimization (Weeks 14-15)

**Goal**: Performance and cost optimization

**Features**: - \[ \] Smart serialization (qs for R objects, Arrow for
data frames) - \[ \] Parallel multipart S3 uploads - \[ \] Result
streaming for large outputs - \[ \] Automatic cleanup of S3 files - \[
\] Task batching for small jobs

**Deliverable**: Fast data transfer, minimal overhead

**Testing**: - Benchmark serialization methods - Test with large objects
(1GB+) - Measure overhead at scale

### Phase 8: Monitoring & Debugging (Week 16)

**Goal**: Tools for debugging and monitoring

**Features**: - \[ \] CloudWatch Logs integration - \[ \]
[`starburst_logs()`](https://scttfrdmn.github.io/starburst/reference/starburst_logs.md)
for viewing worker output - \[ \]
[`starburst_status()`](https://scttfrdmn.github.io/starburst/reference/starburst_status.md)
for cluster monitoring - \[ \] Debug mode (keep workers alive) - \[ \]
Better error messages

**Deliverable**: Easy troubleshooting when things go wrong

**Testing**: - Inject various errors - Test log retrieval - Verify error
messages are helpful

### Phase 9: Documentation & Examples (Weeks 17-18)

**Goal**: Comprehensive documentation and real-world examples

**Features**: - \[ \] Complete function documentation - \[ \] Getting
started vignette - \[ \] Advanced usage vignette - \[ \] Troubleshooting
guide - \[ \] Example workflows (genomics, simulations, bootstrapping) -
\[ \] Performance tuning guide

**Deliverable**: Users can get started and succeed independently

### Phase 10: Testing & Hardening (Weeks 19-20)

**Goal**: Production-ready reliability

**Features**: - \[ \] Comprehensive unit test suite (\>80% coverage) -
\[ \] Integration tests with AWS - \[ \] Load testing (1000+ workers) -
\[ \] Cost regression tests - \[ \] Security audit - \[ \] Performance
benchmarks

**Deliverable**: Stable, tested, production-ready package

## Post-v1.0 Roadmap

### v1.1: GPU Support

**Features**: - EC2 backend (instead of Fargate) - GPU instance types
(g4dn, p3, etc.) - CUDA image building - GPU memory management

**Use Cases**: Deep learning, GPU-accelerated simulations

### v1.2: Spot Instances

**Features**: - Spot pricing for cost savings - Interruption handling
with checkpointing - Spot/on-demand hybrid execution

**Use Cases**: Long-running, interruption-tolerant workloads

### v1.3: EMR/Spark Integration

**Features**: - EMR cluster backend - sparklyr integration - Distributed
data processing

**Use Cases**: Big data analytics, distributed joins

### v1.4: Advanced Features

**Features**: - Custom VPC support - Multi-region execution - Adaptive
scaling based on workload - Smart backend selection (Fargate vs EC2)

## Technical Debt to Address

1.  **Error Handling**: Comprehensive try-catch blocks, better error
    messages
2.  **Retry Logic**: Exponential backoff for transient failures
3.  **Cleanup**: Ensure resources are always cleaned up, even on crashes
4.  **Testing**: Mock AWS services for faster unit tests
5.  **Performance**: Profile and optimize hot paths
6.  **Security**: IAM role review, least-privilege principle

## Success Metrics

**Adoption**: - GitHub stars: 100+ within 3 months - Monthly active
users: 50+ within 6 months - CRAN downloads: 1000+ within 1 year

**Performance**: - Overhead \<10% for workloads \>10 minutes -
Environment sync \<30 seconds (cached) - Support 1000+ concurrent
workers

**Reliability**: - \<1% task failure rate (excluding user code errors) -
Zero data loss - Clean resource cleanup 100% of time

**User Satisfaction**: - Average setup time \<5 minutes - “Just works”
for 90% of use cases - Positive user feedback on ease of use

## Dependencies

**R Packages**: - `future`: Core parallel computing framework - `paws`:
AWS SDK for R - `qs`: Fast serialization - `renv`: Package management -
`arrow`: Efficient data frame serialization

**AWS Services**: - Fargate: Container execution - S3: Data storage -
ECR: Docker image registry - ECS: Container orchestration - Service
Quotas: Quota management - CloudWatch Logs: Monitoring

**External Tools**: - Docker: Image building - AWS CLI: Optional, for
manual operations

## Risk Mitigation

**Risk**: AWS quota limitations - **Mitigation**: Wave-based execution,
proactive quota increase requests

**Risk**: Fargate cold start latency - **Mitigation**: Clear
communication, only use for \>5 min workloads

**Risk**: Cost runaway - **Mitigation**: Cost limits, alerts, automatic
shutdown

**Risk**: Environment mismatch - **Mitigation**: renv-based
reproducibility, validation checks

**Risk**: Data transfer bottleneck - **Mitigation**: Smart
serialization, parallel uploads, compression

## Open Questions

1.  **Container registry**: ECR vs Docker Hub vs both?
    - **Decision**: ECR for simplicity, private by default
2.  **Network**: VPC per user vs shared VPC?
    - **Decision**: Start with default VPC, custom VPC in v1.4
3.  **Authentication**: IAM roles vs access keys?
    - **Decision**: Support both, prefer IAM roles
4.  **Pricing**: Free vs paid tiers?
    - **Decision**: Package is free (MIT), users pay AWS costs
5.  **Support**: Community vs commercial?
    - **Decision**: Start community, consider commercial later

## Team & Resources

**Core Development**: 1 person, 20 weeks full-time equivalent

**Skills Required**: - R package development - AWS (Fargate, S3, ECR,
ECS) - Docker - Parallel computing concepts

**Infrastructure Costs** (development): - AWS services:
~\$50-100/month - CI/CD: GitHub Actions (free) - Documentation hosting:
GitHub Pages (free)

## Timeline Summary

- **Weeks 1-4**: MVP (single worker)
- **Weeks 5-8**: Environment sync + parallel execution
- **Weeks 9-12**: Quota management + setup wizard
- **Weeks 13-16**: Cost tracking + optimization + monitoring
- **Weeks 17-20**: Documentation + testing + hardening
- **Week 21**: v1.0 release

**Total**: ~5 months to v1.0

## Next Steps

1.  Set up development environment
2.  Create GitHub repository
3.  Implement Phase 1 (MVP)
4.  Get feedback from early users
5.  Iterate based on feedback
6.  Continue through roadmap phases

## Getting Involved

Contributions welcome! See CONTRIBUTING.md for guidelines.

Areas where help is needed: - Testing on different R environments -
Documentation and examples - Performance optimization - Feature requests
and bug reports
