# Testing Let's Encrypt Certbot Helper (lecbh)

lecbh is tested inside a disposable Ubuntu 24.04 container running Apache (port 80) and Nginx (port 8080). Certbot is replaced by a mock in `--test-mode`, so no certificates are requested from Let's Encrypt.

## Prerequisites

*   Docker with the Compose v2 plugin (`docker compose`). The standalone v2 `docker-compose` binary is used as a fallback.
*   [Bats](https://github.com/bats-core/bats-core) and `jq` for unit tests (`sudo apt-get install bats jq` on Ubuntu 24.04).
*   [ShellCheck](https://www.shellcheck.net/) for linting (optional locally, enforced in CI).

The container needs no privileged mode, systemd, or host port mappings.

## Unit Tests (Bats)

```
bats tests/bats
```

No root, Docker, or network is needed. The tests cover the pure functions in `lib/core.sh` (validation, domain splitting, Certbot arguments, JSON escaping, exact JSON key order), flag parsing, `flock` lock acquisition, and the CLI dispatcher (`version`, `--version`, `version --json`, `help`, unknown commands, root requirement for `issue`, symlinked invocation, missing `lib/`). Run them as a non-root user too: the root-requirement test is skipped when run as root.

Use the `refute` helper from `tests/bats/test_helper.bash` to assert failure; a bare `! cmd` does not fail a Bats test unless it is the last command.

## Integration Tests

```
./test.sh
```

This builds the image, waits for Apache and Nginx to become healthy, runs the suite, prints a summary, and removes the container (also on failure or Ctrl-C). The script exits non-zero if any test fails.

Lint the scripts:

```
shellcheck -x lecbh.sh lib/*.sh test.sh tests/bats/*.bats tests/bats/*.bash
```

### Test semantics

*   `expect_pass NAME CMD` passes only if `CMD` exits 0.
*   `expect_fail NAME PATTERN CMD` passes only if `CMD` exits non-zero **and** its output matches `PATTERN`. An unrelated crash does not count as the expected failure.
*   Commands run with `bash -o pipefail`. Use `grep … >/dev/null` instead of `grep -q` after a pipe: `grep -q` exits early and the upstream command's SIGPIPE would fail the pipeline.

### Coverage

*   Help output, `version`/`--version`/`version --json`, explicit `issue` command, unknown commands
*   Apache/Nginx dry runs, verbose mode
*   Forwarding of `--staging`, multiple domains, `certonly --dry-run`, and omission of `--email` when none is set
*   `--json`: valid JSON, exact key set, field types/values, `--no-redirect`/`--staging`/server reflected, and empty stdout on failure (validated with `jq`)
*   Rejection of invalid domains (including IP addresses), invalid emails, wildcard domains, unknown servers, and unknown options
*   `flock` concurrency lock: a second concurrent run is refused, and the lock is released afterwards
*   Snap path failing cleanly when snapd is absent
*   Pip path installing Certbot and the Nginx plugin into the `/opt/certbot` virtualenv with a `/usr/bin/certbot` symlink (requires network access to PyPI)

## Manual Testing

```
docker compose up -d --build --wait
docker compose exec lecbh-test bash

./lecbh.sh --help
./lecbh.sh version --json
./lecbh.sh --dry-run --unattended --test-mode --server=apache
./lecbh.sh --dry-run --unattended --test-mode --server=nginx --verbose
./lecbh.sh --dry-run --unattended --test-mode --domains=example.com,www.example.com --json | jq .

exit
docker compose down
```

`lecbh.sh` and `lib/` are bind-mounted read-only into the container, so edits on the host take effect without rebuilding.

## Continuous Integration

GitHub Actions workflows in `.github/workflows/`:

*   `test.yml` runs the Bats unit tests and `./test.sh` as separate jobs on `ubuntu-24.04`.
*   `shellcheck.yml` lints every tracked `*.sh`, `*.bats` and `*.bash` file with `shellcheck -x`. Any finding fails the build.

## Troubleshooting

**Container never becomes healthy**: run `docker compose logs`. Apache must listen on port 80 and Nginx on 8080 inside the container.

**Pip test fails**: the pip installer path downloads Certbot from PyPI. Check network access from Docker.

**Snap**: snapd does not work in standard containers. The suite only verifies that the snap path fails with a clear message. Test real snap installs on a VM.

**Testing with real domains**: run on a server whose public DNS points to it, without `--test-mode`, and use `--staging` first to avoid rate limits.
