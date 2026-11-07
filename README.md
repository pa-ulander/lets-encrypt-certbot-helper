[![Test Status](https://github.com/pa-ulander/lets-encrypt-certbot-helper/actions/workflows/test.yml/badge.svg?branch=main)]![](https://ghvc.kabelkultur.se?username=pa-ulander&label=Repository%20visits&color=brightgreen&style=flat&repository=lets-encrypt-certbot-helper)

# Let's Encrypt Certbot Helper

**Let's Encrypt Certbot Helper** (lecbh) is a lightweight bash script that automates SSL certificate setup using Certbot on Ubuntu servers running Apache or Nginx.

## Table of Contents

- [Let's Encrypt Certbot Helper](#lets-encrypt-certbot-helper)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Usage](#usage)
    - [Basic Usage](#basic-usage)
    - [Command Line Options](#command-line-options)
    - [Examples](#examples)
    - [Default Configuration](#default-configuration)
  - [JSON Output Mode](#json-output-mode)
  - [Concurrency Lock](#concurrency-lock)
  - [Certificate Renewal](#certificate-renewal)
  - [Development and Testing](#development-and-testing)
  - [Troubleshooting](#troubleshooting)
    - [Common Issues](#common-issues)
    - [Logs](#logs)
  - [Contributing](#contributing)
  - [License](#license)
  - [Acknowledgments](#acknowledgments)

## Features

*   Obtains certificates and configures Apache or Nginx to serve them over HTTPS
*   Supports both Apache and Nginx web servers
*   Sets up automatic certificate renewal
*   Validates domain and optional contact email before requesting certificates
*   Supports multiple domains in a single certificate
*   Includes dry-run mode to exercise issuance without installing a certificate
*   Provides staging mode for development without hitting rate limits
*   Works with unattended mode for automated deployments
*   Supports installation via Snap (default) or pip in a virtual environment
*   Includes test mode for Docker/container environments
*   JSON output mode for automation (`--json`)
*   Concurrency lock to prevent overlapping runs

## Requirements

*   Ubuntu with Apache2 or Nginx installed
*   Domain name(s) pointing to your server's public IP
*   Ports 80 and 443 open on your firewall

## Installation

Clone the repository:

```
git clone https://github.com/pa-ulander/lets-encrypt-certbot-helper.git
cd lets-encrypt-certbot-helper
```

Make the script executable:

```
chmod +x lecbh.sh
```

`lecbh.sh` loads its helpers from the `lib/` directory next to it. Keep `lib/` alongside the script when copying it elsewhere; symlinking `lecbh.sh` (e.g. into `/usr/local/bin`) works.

## Usage

### Basic Usage

Run the script with sudo:

```
sudo ./lecbh.sh
```

The script will prompt you for:

*   Domain name(s) (comma-separated for multiple domains)
*   Optional email address for Let's Encrypt registration
*   Web server type (Apache or Nginx)
*   Installation method (snap or pip)

### Command Line Options

```
Usage: sudo ./lecbh.sh [COMMAND] [OPTIONS]

Commands:
  issue                    Obtain and install a certificate (default when omitted)
  version                  Print the lecbh version (JSON with --json)
  help                     Show help

Options:
  --dry-run                Test issuance without installing a certificate
  --unattended             Non-interactive (use defaults / flags)
  --verbose                Extra logging
  --quiet                  Minimal output
  --staging                Use Let's Encrypt staging API
  --test-mode              Mock certbot (for CI / containers)
  --pip / --snap           Select install method (default: snap)
  --server=apache|nginx    Web server type
  --email=ADDR             Optional account email
  --domains=a.com,b.com    Comma separated domains list
  --no-redirect            Disable HTTP→HTTPS redirect
  --json                   Emit JSON summary (implies --quiet)
  --version                Same as the version command
  --help, -h               Show help
```

Running without a command is the same as `issue`, so existing invocations keep working. `version` and `help` do not require root.

### Examples

Test run without making changes:

```
sudo ./lecbh.sh --dry-run
```

Run with default values without prompting:

```
sudo ./lecbh.sh --unattended
```

Use staging environment for development:

```
sudo ./lecbh.sh --staging
```

Show detailed output:

```
sudo ./lecbh.sh --verbose
```

Use pip installation method instead of snap (installed in /opt/certbot):

```
sudo ./lecbh.sh --pip
```

Testing in container environments:

```
sudo ./lecbh.sh --test-mode
```

### Default Configuration

Defaults can be overridden via environment variables or flags. Examples:

```
export DEFAULT_EMAIL="ops@yourdomain.com"
export DEFAULT_DOMAINS="example.com,www.example.com"
export DEFAULT_SERVER="nginx"
export DEFAULT_INSTALL_METHOD="pip"
sudo ./lecbh.sh --unattended
```

Inline override:

```
DEFAULT_EMAIL=ops@yourdomain.com DEFAULT_DOMAINS="example.org,www.example.org" \
  sudo ./lecbh.sh --unattended --server=nginx
```
## JSON Output Mode

Use `--json` to produce a machine-readable summary on stdout. Certbot progress and errors go to stderr, so successful output can be parsed directly. Failed runs exit non-zero and do not emit a success summary.

```
sudo ./lecbh.sh --unattended --server=nginx \
  --domains=example.org,www.example.org --email=admin@example.org --json
```

Sample (values illustrative):

```json
{
  "domains": ["example.org","www.example.org"],
  "email": "admin@example.org",
  "server": "nginx",
  "install_method": "snap",
  "dry_run": false,
  "staging": false,
  "test_mode": false,
  "redirect": true,
  "timestamp": "2025-01-01T00:00:00Z",
  "version": "1.2.0"
}
```

Fields always appear in this order. The full schema, including `lecbh version --json` (`{"version": "1.2.0"}`), is documented in [docs/json-schema.md](docs/json-schema.md).

Parse with `jq`:

```
sudo ./lecbh.sh --unattended --json | jq -r '.domains[]'
```

## Concurrency Lock

The script uses `flock` on a lock file (`/var/run/lecbh.lock` by default) to prevent overlapping runs. Override with `LECBH_LOCK_FILE` if needed. The lock file may remain after exit; the kernel releases the lock automatically.


## Certificate Renewal

The account email is optional. Since June 2025, Let's Encrypt no longer sends expiration notification emails; renewal monitoring must be configured separately.

Let's Encrypt certificate lifetimes are being shortened. The default (`classic`) profile issues 90-day certificates today, 64-day certificates from February 10, 2027, and 45-day certificates from February 16, 2028. Authorization reuse shrinks at the same time, so most renewals will revalidate your domains: port 80 must stay reachable for every renewal, not just the first issuance. Keep automatic renewal operational and monitor it independently:

*   With snap installation: Certbot's snap provides a systemd timer for automatic renewal.
*   With pip installation: lecbh installs a cron job every 12 hours with a randomized delay.
*   Certbot 4.1+ checks ACME Renewal Info (ARI) during `certbot renew` and renews when Let's Encrypt suggests, typically at about two thirds of the lifetime, or earlier if the CA asks (for example, before a mass revocation). Snap installs update automatically; for pip installs, upgrade with `sudo /opt/certbot/bin/pip install --upgrade certbot certbot-apache` (or `certbot-nginx`). Do not rely on a fixed "renew 30 days before expiry" rule.
*   Let's Encrypt also offers opt-in [certificate profiles](https://letsencrypt.org/docs/profiles/), such as `tlsserver` (45 days now). lecbh does not select a profile yet (planned for M3); it uses the CA default.
*   On successful issuance, the selected Apache/Nginx plugin installs the certificate. `--dry-run` exercises issuance only and does not change web-server configuration.

You can test the renewal process with:

```
sudo certbot renew --dry-run
```

To check the status of the renewal timer (snap installation):

```
systemctl status snap.certbot.renew.timer
```

To check the cron job (pip installation):

```
crontab -l | grep certbot
```

## Development and Testing

For development and testing, use the `--staging` flag to avoid rate limits, and `--test-mode` to mock certbot operations inside CI or container environments.

Pure logic (flag parsing, validation, Certbot arguments, JSON) lives in `lib/core.sh`, logging in `lib/logging.sh`, and locking in `lib/lock.sh`; `lecbh.sh` holds the side-effecting steps and the command dispatcher.

Run `bats tests/bats` for the fast unit tests (needs [Bats](https://github.com/bats-core/bats-core) and `jq`), and `./test.sh` for the integration suite in a disposable Ubuntu 24.04 container (requires Docker Compose v2). CI runs both plus a blocking ShellCheck lint.

For detailed information about testing procedures and environments, see the [Testing documentation](Testing.md).

## Troubleshooting

### Common Issues

**Domain not reachable**: Ensure your domain's DNS records point to your server's IP address.

**Port 80/443 not accessible**: Check your firewall settings and ensure your web server is properly configured.

**Web server not running**: Make sure Apache or Nginx is installed and running.

**Rate limits**: If you hit Let's Encrypt rate limits, use the `--staging` flag for testing.

**Snap not available**: If snap is not available or preferred, use `--pip` to install in a virtual environment. Certbot documents pip support as best-effort; prefer the system-recommended installation method when possible.

### Logs

Certbot logs can be found at:

*   `/var/log/letsencrypt/letsencrypt.log`

## Contributing

Issues, pull requests, code reviews, and feedback are welcome. See the [contributing guide](CONTRIBUTING.md) for the development workflow and project conventions.


## Acknowledgments

*   [Let's Encrypt](https://letsencrypt.org/) for providing free SSL certificates
*   [Certbot](https://certbot.eff.org/) for the excellent certificate management tool

## MIT License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

