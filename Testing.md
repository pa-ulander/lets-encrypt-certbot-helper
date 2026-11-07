# Testing Let's Encrypt Certbot Helper (lecbh)

lecbh is tested inside a disposable Ubuntu 24.04 container running Apache (port 80) and Nginx (port 8080). Certbot is replaced by a mock in `--test-mode`, so no certificates are requested from Let's Encrypt.

## Prerequisites

*   Docker with the Compose v2 plugin (`docker compose`). The standalone v2 `docker-compose` binary is used as a fallback.
*   [ShellCheck](https://www.shellcheck.net/) for linting (optional locally, enforced in CI).

The container needs no privileged mode, systemd, or host port mappings.

## Running the Tests

```
./test.sh
```

This builds the image, waits for Apache and Nginx to become healthy, runs the suite, prints a summary, and removes the container (also on failure or Ctrl-C). The script exits non-zero if any test fails.

Lint the scripts:

```
shellcheck lecbh.sh test.sh
```

### Test semantics

*   `expect_pass NAME CMD` passes only if `CMD` exits 0.
*   `expect_fail NAME PATTERN CMD` passes only if `CMD` exits non-zero **and** its output matches `PATTERN`. An unrelated crash does not count as the expected failure.
*   Commands run with `bash -o pipefail`. Use `grep … >/dev/null` instead of `grep -q` after a pipe: `grep -q` exits early and the upstream command's SIGPIPE would fail the pipeline.

### Coverage

*   Help output, Apache/Nginx dry runs, verbose mode
*   Forwarding of `--staging`, multiple domains, `certonly --dry-run`, and omission of `--email` when none is set
*   `--json`: valid JSON, exact key set, field types/values, `--no-redirect`/`--staging`/server reflected, and empty stdout on failure (validated with `jq`)
*   Rejection of invalid domains, invalid emails, wildcard domains, unknown servers, and unknown options
*   `flock` concurrency lock: a second concurrent run is refused, and the lock is released afterwards
*   Snap path failing cleanly when snapd is absent
*   Pip path installing Certbot and the Nginx plugin into the `/opt/certbot` virtualenv with a `/usr/bin/certbot` symlink (requires network access to PyPI)

## Manual Testing

```
docker compose up -d --build --wait
docker compose exec lecbh-test bash

./lecbh.sh --help
./lecbh.sh --dry-run --unattended --test-mode --server=apache
./lecbh.sh --dry-run --unattended --test-mode --server=nginx --verbose
./lecbh.sh --dry-run --unattended --test-mode --domains=example.com,www.example.com --json | jq .

exit
docker compose down
```

`lecbh.sh` is bind-mounted read-only into the container, so edits on the host take effect without rebuilding.

## Continuous Integration

GitHub Actions workflows in `.github/workflows/`:

*   `test.yml` runs `./test.sh` on `ubuntu-24.04`.
*   `shellcheck.yml` lints every tracked `*.sh` file. Any finding fails the build.

## Troubleshooting

**Container never becomes healthy**: run `docker compose logs`. Apache must listen on port 80 and Nginx on 8080 inside the container.

**Pip test fails**: the pip installer path downloads Certbot from PyPI. Check network access from Docker.

**Snap**: snapd does not work in standard containers. The suite only verifies that the snap path fails with a clear message. Test real snap installs on a VM.

**Testing with real domains**: run on a server whose public DNS points to it, without `--test-mode`, and use `--staging` first to avoid rate limits.
