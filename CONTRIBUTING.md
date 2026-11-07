# Contributing to lecbh

Thanks for your interest in improving lecbh. This guide covers the development workflow and project conventions.

## Quick Start

```bash
git clone https://github.com/pa-ulander/lets-encrypt-certbot-helper.git
cd lets-encrypt-certbot-helper
bats tests/bats
./test.sh
```

The unit tests need Bats and `jq`; the integration suite needs Docker Compose v2 and network access for the pip Certbot test.

## Development Workflow

1. Create a focused branch, for example `git checkout -b fix/short-description`.
2. Make changes with tests and documentation updates where appropriate.
3. Run the relevant checks:
   ```bash
   bats tests/bats
   ./test.sh
   shellcheck -x lecbh.sh lib/*.sh test.sh tests/bats/*.bats tests/bats/*.bash
   ```
4. Update the `[Unreleased]` section of `CHANGELOG.md` for user-visible changes.
5. Open a pull request and ensure CI passes.

## Project Conventions

- Keep pure logic in `lib/*.sh`; keep network and filesystem side effects in thin wrappers.
- Keep `lib/` next to `lecbh.sh`; the entry point sources its libraries relative to its own path.
- Preserve the JSON output schema. If JSON keys or types change, update `docs/json-schema.md` and the relevant tests.
- Avoid new external dependencies and do not change security-sensitive defaults without documenting why.
- Use Bash arrays for command construction and avoid `eval`.
- Keep `set -euo pipefail` and follow the existing Bash style.
- In Bats tests, use the `refute` helper from `tests/bats/test_helper.bash` to assert that a command fails. A bare `! command` can silently pass when followed by more commands.

## Commit Style

Conventional Commit prefixes are encouraged:

- `feat:` user-facing feature
- `fix:` bug fix
- `docs:` documentation only
- `refactor:` internal change
- `test:` tests only
- `chore:` maintenance

## Proposing Larger Changes

For changes to command interfaces, plugin architecture, or security-sensitive behavior, open or discuss a design issue before implementation. The active milestones and design questions are tracked in the repository's GitHub issues.

## Reporting Bugs

Use the bug report issue template. Include what happened versus what you expected, reproduction commands, the OS and install method, and relevant output with sensitive details removed.

## Security

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md). Do not include sensitive vulnerability details in a public issue.

## Code of Conduct

Participation in this project is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
