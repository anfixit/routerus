# Contributing to RouteRus

## Reporting bugs

1. Check [Issues](https://github.com/anfixit/routerus/issues) first
2. Create a new issue with:
   - Problem description
   - Steps to reproduce
   - Expected vs actual behavior
   - Ubuntu and RouteRus versions
   - Relevant logs

## Feature requests

1. Create an issue with the `enhancement` label
2. Describe: why it's needed, how it should work, usage examples

## Pull requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run `shellcheck` on all modified scripts
5. Test on a clean Ubuntu 24.04 installation
6. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat:` new feature
   - `fix:` bug fix
   - `docs:` documentation changes
   - `refactor:` code restructuring
   - `chore:` maintenance tasks
7. Push and open a pull request

## Code standards

### Shell scripts
- Start with `#!/bin/bash`
- Use `set -euo pipefail`
- Quote all variables: `"${var}"`
- Use `[[ ]]` instead of `[ ]`
- Validate with `shellcheck`
- Use functions from `helpers.sh` for output formatting

### JSON configs
- Validate with `jq empty config.json`
- Use 2-space indentation

## Project structure

See [STRUCTURE.md](STRUCTURE.md).

## Questions?

- GitHub Discussions
- Issues with the `question` label
