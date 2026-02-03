# Contributing to staRburst

Thank you for your interest in contributing to staRburst! This document provides guidelines for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/starburst.git`
3. Create a branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Run tests: `devtools::test()`
6. Run checks: `devtools::check()`
7. Commit: `git commit -m "Description of changes"`
8. Push: `git push origin feature/your-feature-name`
9. Open a Pull Request

## Development Setup

```r
# Install development dependencies
install.packages(c("devtools", "testthat", "roxygen2", "pkgdown"))

# Load package for development
devtools::load_all()

# Run tests
devtools::test()

# Build documentation
devtools::document()

# Check package
devtools::check()
```

## Code Style

- Follow the [tidyverse style guide](https://style.tidyverse.org/)
- Use `roxygen2` for documentation
- Write tests for new functions
- Keep functions focused and modular

## Testing

- Write tests for all new functionality
- Place tests in `tests/testthat/test-*.R`
- Use descriptive test names
- Mock AWS API calls when possible

```r
test_that("function does what it should", {
  expect_equal(my_function(1), 2)
})
```

## Documentation

- Document all exported functions with `roxygen2`
- Include `@examples` for user-facing functions
- Update vignettes if adding major features
- Keep README.md up to date

## Pull Request Process

1. Update NEWS.md with your changes
2. Ensure all tests pass
3. Update documentation if needed
4. Request review from maintainers
5. Address review comments
6. Merge when approved

## Areas for Contribution

See [issues](https://github.com/yourusername/starburst/issues) for specific tasks.

Priority areas:
- Docker image building implementation
- Additional serialization methods
- Performance optimization
- Documentation improvements
- Example workflows

## Questions?

- Open an issue for bugs or feature requests
- Use discussions for questions
- Email maintainers for sensitive issues

## Code of Conduct

Be respectful and inclusive. We want staRburst to be welcoming to all contributors.
