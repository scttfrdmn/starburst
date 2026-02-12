# Claude Development Guide for staRburst

This document provides guidelines for Claude (or other AI assistants) working on the staRburst project.

## Project Overview

**staRburst** is an R package that enables seamless AWS cloud bursting for parallel R workloads using AWS Fargate and ECS. It provides a `future` backend that allows users to scale from local execution to 100+ cloud workers with a single line of code change.

## Repository Information

- **GitHub**: https://github.com/scttfrdmn/starburst
- **Primary Language**: R
- **Cloud Platform**: AWS (Fargate, ECS, S3, ECR)
- **License**: Apache 2.0

## Project Management

### GitHub Issues & Milestones

We use **GitHub Issues** and **Milestones** to track all development work:

#### Viewing Issues
```bash
# List open issues
gh issue list --repo scttfrdmn/starburst

# View specific issue
gh issue view <number> --repo scttfrdmn/starburst

# Search issues by label
gh issue list --label "type:bug" --repo scttfrdmn/starburst
gh issue list --label "priority:high" --repo scttfrdmn/starburst
```

#### Creating Issues
When you identify bugs, needed features, or improvements:

```bash
# Create a bug report
gh issue create --repo scttfrdmn/starburst \
  --title "Bug: [brief description]" \
  --body "**Description:**
[Detailed description]

**Steps to Reproduce:**
1. [Step 1]
2. [Step 2]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Environment:**
- staRburst version: [version]
- R version: [version]
- AWS region: [region]" \
  --label "type:bug,priority:high"

# Create a feature request
gh issue create --repo scttfrdmn/starburst \
  --title "Feature: [brief description]" \
  --body "**Use Case:**
[Why is this needed]

**Proposed Solution:**
[How to implement]

**Alternatives Considered:**
[Other approaches]" \
  --label "type:feature,priority:medium"
```

#### Closing Issues
When work is completed, close issues with detailed comments:

```bash
gh issue close <number> --repo scttfrdmn/starburst \
  --comment "✅ Completed in commit <hash>

[Detailed description of what was implemented]

Files changed: [list key files]
Tests: [test coverage added]
Status: [Production ready/Needs review/etc]"
```

#### Milestones
Track related work using milestones:

```bash
# List milestones
gh milestone list --repo scttfrdmn/starburst

# Add issue to milestone
gh issue edit <number> --milestone "Milestone Name" --repo scttfrdmn/starburst
```

### Label System

Use labels to categorize issues:

**Priority:**
- `priority:critical` - Security issues, data loss, production blockers
- `priority:high` - Important features, significant bugs
- `priority:medium` - Nice-to-have features, minor bugs
- `priority:low` - Future enhancements, low-impact issues

**Type:**
- `type:bug` - Something isn't working
- `type:feature` - New feature or enhancement
- `type:docs` - Documentation improvements
- `type:infrastructure` - AWS/infrastructure changes
- `type:testing` - Testing improvements

**Area:**
- `area:aws` - AWS integration (ECS, S3, ECR)
- `area:docker` - Docker/containerization
- `area:core` - Core functionality
- `area:future` - Future backend integration

**Status:**
- `status:blocked` - Blocked by dependencies
- `status:in-progress` - Currently being worked on

**Other:**
- `performance` - Performance improvements
- `breaking-change` - Breaking API changes (requires major version bump)
- `help-wanted` - Community contributions welcome
- `good-first-issue` - Good for new contributors

## Development Workflow

### Before Starting Work

1. **Check for related issues**
   ```bash
   gh issue list --label "area:relevant" --repo scttfrdmn/starburst
   ```

2. **Create or claim an issue**
   - If no issue exists, create one
   - Add `status:in-progress` label when starting work

3. **Review existing code**
   - Read relevant source files
   - Check test coverage
   - Review recent commits

### During Development

1. **Follow R Best Practices**
   - Use `devtools::load_all()` for testing
   - Run `devtools::check()` before committing
   - Add tests for new functionality
   - Document functions with roxygen2

2. **Test Thoroughly**
   ```r
   # Run all tests
   devtools::test()

   # Run specific test file
   testthat::test_file("tests/testthat/test-security.R")

   # Integration tests with AWS
   AWS_PROFILE=aws devtools::test()
   ```

3. **Update Documentation**
   - Update function documentation (roxygen2 comments)
   - Update vignettes if needed
   - Update README.md if adding major features

### Committing Changes

Follow the commit message format:

```
<type>: <short description>

<detailed description>

<breaking changes if any>

Closes: #<issue-number>
```

**Commit types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `test:` - Adding or updating tests
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `chore:` - Maintenance tasks

**Example:**
```bash
git commit -m "feat: Add worker validation with max 500 limit

Prevents accidental massive deployments that could incur significant costs.
Validates worker count in plan() and enforces maximum of 500 workers.

Closes: #123
Verified: AWS integration tests passed"
```

### After Completing Work

1. **Close related issues**
   ```bash
   gh issue close <number> --repo scttfrdmn/starburst \
     --comment "✅ Completed in commit <hash>"
   ```

2. **Update milestone progress**
   - Ensure issue is associated with correct milestone
   - Check milestone completion status

3. **Create follow-up issues if needed**
   - Document any discovered issues
   - Create issues for future improvements

## Code Quality Standards

### Security
- Never hard-code AWS credentials
- Use `safe_system()` for all external command execution
- Validate all user inputs
- Follow security best practices from `vignettes/security.Rmd`

### Performance
- Minimize AWS API calls
- Use retry logic for transient failures
- Implement proper timeout handling
- Consider cost implications of all operations

### Testing
- Write tests for all new functionality
- Aim for >80% code coverage
- Include integration tests for AWS operations
- Test error handling paths

### Documentation
- All exported functions must have roxygen2 documentation
- Include examples in function documentation
- Update vignettes for major features
- Keep README.md current

## AWS Integration Testing

Test changes against real AWS infrastructure:

```bash
# Set AWS profile
export AWS_PROFILE=aws

# Run tests
Rscript -e "devtools::test()"

# Test specific functionality
Rscript -e "
devtools::load_all()
# Your test code here
"
```

**Important:** Always verify AWS integration for:
- Security changes
- Resource management changes
- Reliability improvements
- New AWS service integrations

## Common Tasks

### Adding a New Feature

1. Create issue: `gh issue create --label "type:feature"`
2. Add to appropriate milestone
3. Implement with tests
4. Update documentation
5. Test against AWS
6. Commit and push
7. Close issue with detailed comment

### Fixing a Bug

1. Create issue: `gh issue create --label "type:bug,priority:high"`
2. Write failing test
3. Fix the bug
4. Verify test passes
5. Add regression test
6. Commit and push
7. Close issue

### Improving Documentation

1. Create issue: `gh issue create --label "type:docs"`
2. Update relevant files (vignettes, README, function docs)
3. Build documentation: `devtools::document()`
4. Preview: `devtools::build_vignettes()`
5. Commit and push
6. Close issue

## Resources

- **Troubleshooting Guide**: `vignettes/troubleshooting.Rmd`
- **Security Best Practices**: `vignettes/security.Rmd`
- **AWS Documentation**: https://aws.amazon.com/documentation/
- **R Package Development**: https://r-pkgs.org/
- **Future Package**: https://future.futureverse.org/

## Questions or Issues?

- Create a GitHub issue: https://github.com/scttfrdmn/starburst/issues
- Check existing issues for similar problems
- Review vignettes for common solutions

## Project Milestones

Current active milestones:

- **Production Ready v1.0** (Completed) - Security, reliability, documentation
- **v0.3.0 - Public Base Images** - Reduce Docker build times
- **v0.4.0 - Advanced Features** - Spot instances, advanced monitoring
- **v1.0.0 - Production Release** - CRAN submission ready

Check milestone progress: https://github.com/scttfrdmn/starburst/milestones
