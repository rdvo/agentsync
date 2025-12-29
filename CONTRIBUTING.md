# Contributing to agentsync

Thank you for your interest in contributing to agentsync! This document provides guidelines and instructions for contributing.

## Ways to Contribute

- **Bug Reports**: Found a bug? Open an issue with details about what happened and how to reproduce it.
- **Feature Requests**: Have an idea for a new feature? Open an issue to discuss it.
- **Code Contributions**: Want to add a feature or fix a bug? Submit a pull request.
- **Documentation**: Improve the README, add examples, or create documentation.

## Development Setup

1. **Fork the repository**
2. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR-USERNAME/agentsync.git
   cd agentsync
   ```

3. **Install dependencies**:
   ```bash
   # For testing
   brew install bats      # macOS
   sudo apt-get install bats shellcheck  # Linux

   # For development
   npm install
   ```

4. **Create a feature branch**:
   ```bash
   git checkout -b feature/my-new-feature
   ```

## Testing

Run the test suite:

```bash
# Run all tests
npm test

# Run specific test file
bats tests/utils.bats

# Run with coverage
bats --formatter junit tests/
```

## Linting

Before submitting, run the linter:

```bash
npm run lint
npm run lint:fix
```

## Code Style

- Follow existing code conventions in the project
- Use descriptive variable and function names
- Add comments for complex logic
- Keep functions focused and single-purpose

## Submitting Changes

1. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add feature: description of changes"
   ```

2. **Push to your fork**:
   ```bash
   git push origin feature/my-new-feature
   ```

3. **Open a Pull Request**:
   - Go to the original repository
   - Click "New Pull Request"
   - Select your branch and submit

## Adding New Tool Support

To add support for a new AI tool:

1. Update `lib/detect.sh`:
   - Add the tool to `TOOL_DIRS` and `TOOL_CONFIGS`
   - Add display name in `get_tool_display_name()`

2. Update `lib/sync.sh`:
   - Add the tool to `get_default_targets()`
   - Implement sync functions for the tool's specific format

3. Update `README.md`:
   - Add the tool to the feature list
   - Add the tool to the translation table

4. Add tests for the new tool

## Release Process

1. Update version in:
   - `agentsync` (AGENTSYNC_VERSION variable)
   - `package.json` (version field)
   - `README.md` (if mentioned)

2. Create and push a tag:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. GitHub Actions will automatically build and create a release.

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help newcomers get started
