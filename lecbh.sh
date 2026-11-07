#!/usr/bin/env bash

# lecbh - Let's Encrypt Certbot Helper for Apache/Nginx on Ubuntu
# https://github.com/pa-ulander/lecbh
# Version: 1.2.0

set -euo pipefail
IFS=$'\n\t'
LOCK_FILE="${LECBH_LOCK_FILE:-/var/run/lecbh.lock}"
VERSION="1.2.0"
JSON_MODE=false

trap 'exit 130' INT
trap 'exit 143' TERM

# -------------------- DEFAULT CONFIG (env overrides allowed) --------------------
: "${DEFAULT_EMAIL:=}"
: "${DEFAULT_DOMAINS:=example.com}"
: "${DEFAULT_SERVER:=apache}"
: "${DEFAULT_INSTALL_METHOD:=snap}" # snap | pip
: "${LECBH_NO_COLOR:=0}" # set to 1 to disable emojis/colors
# --------------------------------------------------------------------------------

DRY_RUN=false
UNATTENDED=false
VERBOSE=false
STAGING=false
TEST_MODE=false
QUIET=false
NO_REDIRECT=false
INSTALL_METHOD="$DEFAULT_INSTALL_METHOD"

SERVER=""
EMAIL_OVERRIDE=""
DOMAINS_OVERRIDE=""

COLOR_OK="✅"; COLOR_WARN="⚠️"; COLOR_ERR="❌"; COLOR_INFO="🔍"; COLOR_KEY="🔐"
if [[ "$LECBH_NO_COLOR" == "1" ]]; then
    COLOR_OK="[OK]"; COLOR_WARN="[WARN]"; COLOR_ERR="[ERR]"; COLOR_INFO="[INFO]"; COLOR_KEY="[LECBH]"
fi

usage() {
    cat <<EOF
Usage: sudo ./lecbh.sh [OPTIONS]

Options:
    --dry-run                Test issuance without installing a certificate
    --unattended             Non-interactive: use defaults or provided flags
    --verbose                Verbose logging
    --quiet                  Minimal output (overrides verbose)
    --staging                Use Let's Encrypt staging environment
    --test-mode              Do not install real certbot; use mock (CI/testing)
    --pip                    Force pip install method
    --snap                   Force snap install method (default)
    --server=apache|nginx    Web server type (overrides DEFAULT_SERVER)
    --email=ADDR             Optional email address (overrides DEFAULT_EMAIL)
    --domains=a.com,b.com    Comma separated domain list
    --no-redirect            Do not force HTTP->HTTPS redirect
    --json                   Output machine-readable JSON summary (implies quiet except errors)
    --help                   Show this help and exit

Examples:
    sudo ./lecbh.sh --unattended --server=nginx \\
             --domains=example.org,www.example.org --email=admin@example.org
    sudo ./lecbh.sh --dry-run --staging --unattended
EOF
}

log() { if $VERBOSE && ! $QUIET; then echo "${COLOR_INFO} $*" >&2; fi; return 0; }
info() { if ! $QUIET; then echo "$*" >&2; fi; return 0; }
warn() { echo "${COLOR_WARN} $*" >&2; return 0; }
die() { echo "${COLOR_ERR} $*" >&2; exit 1; }

json_quote() {
    printf '"%s"' "$1"
}

parse_flags() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true ;;
            --unattended) UNATTENDED=true ;;
            --verbose) VERBOSE=true ;;
            --quiet) QUIET=true ; VERBOSE=false ;;
            --staging) STAGING=true ;;
            --test-mode) TEST_MODE=true ;;
            --pip) INSTALL_METHOD="pip" ;;
            --snap) INSTALL_METHOD="snap" ;;
            --server=*) SERVER="${1#*=}" ;;
            --email=*) EMAIL_OVERRIDE="${1#*=}" ;;
            --domains=*) DOMAINS_OVERRIDE="${1#*=}" ;;
            --no-redirect) NO_REDIRECT=true ;;
            --json) JSON_MODE=true ; QUIET=true ; VERBOSE=false ;;
            --help) usage; exit 0 ;;
            *) die "Unknown option: $1 (use --help)" ;;
        esac
        shift
    done
}

validate_email() {
    [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] ||
        die "Invalid email: $1"
}

validate_domain() {
    [[ $1 != *'*'* ]] || die "Wildcard domains require DNS-01 validation, which is not supported yet: $1"
    [[ ${#1} -le 253 && $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] ||
        die "Invalid domain: $1"
}

resolve_domain() {
    local d=$1
    if getent ahosts "$d" >/dev/null 2>&1; then
        log "Resolved $d"
        return 0
    else
        warn "Could not resolve domain $d"
        return 1
    fi
}

ensure_root() { [[ $EUID -eq 0 ]] || die "Please run as root (sudo)."; }

ensure_prereqs() {
    command -v nc >/dev/null 2>&1 || { info "Installing netcat-openbsd"; apt-get update -y && apt-get install -y netcat-openbsd >/dev/null 2>&1; }
}

prepare_mock_certbot() {
    local mock_dir="/tmp/lecbh-mock"
    mkdir -p "$mock_dir"
    cat >"$mock_dir/certbot" <<'MOCK'
#!/usr/bin/env bash
echo "[lecbh mock certbot] $*"
if [[ "$*" == *"certificates"* ]]; then
    echo "No certificates found (mock)."
fi
exit 0
MOCK
    chmod +x "$mock_dir/certbot"
    export PATH="$mock_dir:$PATH"
    log "Using mock certbot in test mode"
}

install_certbot() {
    if $TEST_MODE; then
        if [[ "${LECBH_TEST_INSTALL:-0}" == "1" ]]; then
            # Perform real install only once per method to exercise installer path
            local marker="/var/lib/lecbh_real_install_${INSTALL_METHOD}"
            if [[ ! -f $marker ]]; then
                log "Test mode (install): performing one-time real install for method=${INSTALL_METHOD}"
                command -v certbot >/dev/null 2>&1 || {
                    case $INSTALL_METHOD in
                        snap)
                            command -v snap >/dev/null 2>&1 || die "snap command not found; install snapd or use --pip"
                            info "📦 Installing certbot via snap..."
                            snap install core >/dev/null 2>&1 || true
                            snap refresh core >/dev/null 2>&1 || true
                            snap install --classic certbot >/dev/null 2>&1 || die "Failed snap install of certbot"
                            ln -sf /snap/bin/certbot /usr/bin/certbot
                            ;;
                        pip)
                            install_certbot_with_pip
                            ;;
                        *) die "Unknown INSTALL_METHOD: $INSTALL_METHOD" ;;
                    esac
                }
                touch "$marker" || true
            else
                log "Test mode (install): real install already performed (${INSTALL_METHOD})"
            fi
            # Always overlay mock after ensuring real install once
            prepare_mock_certbot
            return 0
        else
            info "${COLOR_INFO} Test mode: forcing mock certbot"
            prepare_mock_certbot
            return 0
        fi
    fi
    # Normal (non-test) path
    if command -v certbot >/dev/null 2>&1; then
        log "Certbot already present"
        return 0
    fi
    case $INSTALL_METHOD in
        snap)
            command -v snap >/dev/null 2>&1 || die "snap command not found; install snapd or use --pip"
            info "📦 Installing certbot via snap..."
            snap install core >/dev/null 2>&1 || true
            snap refresh core >/dev/null 2>&1 || true
            snap install --classic certbot >/dev/null 2>&1 || die "Failed snap install of certbot"
            ln -sf /snap/bin/certbot /usr/bin/certbot
            ;;
        pip)
            install_certbot_with_pip
            ;;
        *) die "Unknown INSTALL_METHOD: $INSTALL_METHOD" ;;
    esac
}

install_certbot_with_pip() {
    local certbot_venv="/opt/certbot"
    local plugin="certbot-${SERVER}"

    info "📦 Installing certbot via pip in ${certbot_venv}..."
    apt-get update -y
    apt-get install -y --no-install-recommends python3-venv libaugeas0
    python3 -m venv "$certbot_venv" || die "Failed to create Certbot virtual environment"
    "$certbot_venv/bin/pip" install --upgrade certbot "$plugin" ||
        die "Failed to install Certbot and ${plugin} in ${certbot_venv}"
    ln -sf "$certbot_venv/bin/certbot" /usr/bin/certbot
}

ensure_server_running() {
    local server=$1
    case $server in
        apache)
            command -v apache2 >/dev/null 2>&1 || die "Apache not installed"
            if ! pgrep -x apache2 >/dev/null 2>&1; then
                service apache2 start >/dev/null 2>&1 || true
            fi
            pgrep -x apache2 >/dev/null 2>&1 || warn "Apache process not detected (continuing)"
            CERTBOT_PLUGIN="--apache"
            ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || die "Nginx not installed"
            if ! pgrep -x nginx >/dev/null 2>&1; then
                service nginx start >/dev/null 2>&1 || true
            fi
            pgrep -x nginx >/dev/null 2>&1 || warn "Nginx process not detected (continuing)"
            CERTBOT_PLUGIN="--nginx"
            ;;
        *) die "Unsupported server: $server" ;;
    esac
}

check_ports() {
    local missing=false
    # Temporarily disable errexit for port probing
    set +e
    nc -z localhost 80 >/dev/null 2>&1
    local p80=$?
    nc -z localhost 443 >/dev/null 2>&1
    local p443=$?
    set -e
    if [[ $p80 -ne 0 ]]; then
        warn "Port 80 not open"; missing=true
    fi
    if [[ $p443 -ne 0 ]]; then
        warn "Port 443 not open (expected after issuance)"
    fi
    if $missing && ! $UNATTENDED; then
        read -r -p "Continue despite port 80 closed? (y/N): " c
        [[ ${c:-n} == y ]] || die "Aborted by user"
    fi
    return 0
}

check_existing_certs() {
    $DRY_RUN || $STAGING || $TEST_MODE || return 0
    return 0 # logic skipped in dry-run/staging/test modes intentionally
}

build_certbot_args() {
    if $DRY_RUN || $TEST_MODE; then
        CERTBOT_ARGS=(certbot certonly)
    else
        CERTBOT_ARGS=(certbot)
    fi
    CERTBOT_ARGS+=("$CERTBOT_PLUGIN")
    for d in "${DOMAINS[@]}"; do CERTBOT_ARGS+=( -d "$d" ); done
    if [[ -n "$EMAIL" ]]; then CERTBOT_ARGS+=( --email "$EMAIL" ); fi
    if $UNATTENDED; then CERTBOT_ARGS+=( --agree-tos --non-interactive ); fi
    if $DRY_RUN; then CERTBOT_ARGS+=( --dry-run ); fi
    if $STAGING; then CERTBOT_ARGS+=( --staging ); fi
    if ! $NO_REDIRECT && ! $DRY_RUN && ! $TEST_MODE; then CERTBOT_ARGS+=( --redirect ); fi
}

run_certbot() {
    info "🚀 Running: ${CERTBOT_ARGS[*]}"
    if $JSON_MODE; then
        "${CERTBOT_ARGS[@]}" >&2 || die "Certbot command failed"
    else
        "${CERTBOT_ARGS[@]}" || die "Certbot command failed"
    fi
    if $DRY_RUN; then
        info "${COLOR_OK} Dry run completed"
    else
        info "${COLOR_OK} Certificate request successful"
    fi
}

test_renewal() {
    ($DRY_RUN || $TEST_MODE) && return 0
    info "🔄 Testing renewal (dry-run)"
    certbot renew --dry-run >/dev/null 2>&1 || warn "Renewal dry-run failed"
    if [[ $INSTALL_METHOD == snap ]]; then
        if systemctl is-active --quiet snap.certbot.renew.timer 2>/dev/null; then
            log "snap.certbot.renew.timer active"
        else
            warn "snap.certbot.renew.timer not active"
        fi
    elif [[ $INSTALL_METHOD == pip ]]; then
        crontab -l 2>/dev/null | grep -q 'certbot renew' || {
            (crontab -l 2>/dev/null; echo "0 */12 * * * sleep \"\$(shuf -i 0-3600 -n 1)\" && /usr/bin/certbot renew --quiet") | crontab -
            log "Installed cron renewal"
        }
    fi
}

final_report() {
    if $TEST_MODE; then
        info "🧪 Test mode complete (no real certificates)"; return
    fi
    if $DRY_RUN; then
        info "🧪 Dry-run finished (no real certificates)"; return
    fi
    if $STAGING; then
        info "🧪 Staging certificates issued (not browser-trusted)"; return
    fi
    info "🔒 Your site should now be accessible via HTTPS."
}

main() {
    parse_flags "$@"
    ensure_root
    info "${COLOR_KEY} lecbh - Let's Encrypt Certbot Helper"
    info "----------------------------------------"

    command -v flock >/dev/null 2>&1 || die "flock is required to safely prevent concurrent runs"
    if ! exec 9>"$LOCK_FILE"; then
        die "Cannot open lock file ($LOCK_FILE)"
    fi
    flock -n 9 || die "Another lecbh instance is running (lock: $LOCK_FILE)"

    # Determine interactive inputs
    DOMAIN_INPUT=${DOMAINS_OVERRIDE:-$DEFAULT_DOMAINS}
    EMAIL=${EMAIL_OVERRIDE:-$DEFAULT_EMAIL}
    SERVER=${SERVER:-$DEFAULT_SERVER}

    if ! $UNATTENDED; then
        read -r -p "🌐 Domains [$DOMAIN_INPUT]: " inp || true; DOMAIN_INPUT=${inp:-$DOMAIN_INPUT}
        read -r -p "📧 Email [$EMAIL]: " inp || true; EMAIL=${inp:-$EMAIL}
        read -r -p "🖥️ Server (apache/nginx) [$SERVER]: " inp || true; SERVER=${inp:-$SERVER}
        read -r -p "🔧 Install method (snap/pip) [$INSTALL_METHOD]: " inp || true; INSTALL_METHOD=${inp:-$INSTALL_METHOD}
    else
        log "Unattended mode values: domains=$DOMAIN_INPUT email=$EMAIL server=$SERVER method=$INSTALL_METHOD"
    fi

    [[ -z "$EMAIL" ]] || validate_email "$EMAIL"
    IFS=',' read -r -a DOMAINS <<<"$DOMAIN_INPUT"
    local cleaned=()
    for d in "${DOMAINS[@]}"; do
        d=$(echo "$d" | xargs)
        [[ -z $d ]] && continue
        validate_domain "$d"
        cleaned+=("$d")
    done
    DOMAINS=("${cleaned[@]}")
    [[ ${#DOMAINS[@]} -gt 0 ]] || die "No valid domains provided"

    resolve_domain "${DOMAINS[0]}" || warn "Primary domain not resolvable"

    ensure_prereqs
    install_certbot
    ensure_server_running "$SERVER"
    check_ports
    check_existing_certs
    build_certbot_args
    run_certbot
    test_renewal
    final_report

    if $JSON_MODE; then
        # Build JSON object
        # Build proper JSON array of domains
        if ((${#DOMAINS[@]})); then
            domains_json="["
            for i in "${!DOMAINS[@]}"; do
                d=${DOMAINS[$i]}
                if [[ $i -gt 0 ]]; then domains_json+=","; fi
                domains_json+="$(json_quote "$d")"
            done
            domains_json+="]"
        else
            domains_json="[]"
        fi
        cat <<JEOF
{
  "domains": $domains_json,
  "email": $(json_quote "$EMAIL"),
  "server": "${SERVER}",
  "install_method": "${INSTALL_METHOD}",
  "dry_run": ${DRY_RUN},
  "staging": ${STAGING},
  "test_mode": ${TEST_MODE},
  "redirect": $(! $NO_REDIRECT && echo true || echo false),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "${VERSION}"
}
JEOF
    else
        info ""
        info "📝 Next steps:"
        info "   1. Test SSL: https://www.ssllabs.com/ssltest/"
        info "   2. Consider enabling HSTS"
        info "   3. Verify HTTP->HTTPS redirect (if enabled)"
    fi
    # Optional delay (for testing lock behavior)
    if [[ -n "${LECBH_SLEEP_BEFORE_EXIT:-}" ]]; then
        sleep "$LECBH_SLEEP_BEFORE_EXIT"
    fi
}

main "$@"
