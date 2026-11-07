#!/usr/bin/env bash
# Integration tests for lecbh, run inside a disposable Ubuntu 24.04 container.
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

cd "$(dirname "$0")" || exit 1

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version 2>/dev/null | grep 'v2' >/dev/null; then
    COMPOSE=(docker-compose)
else
    echo -e "${RED}Docker Compose v2 is required (docker compose).${NC}" >&2
    exit 1
fi

EXPECTED_VERSION=$(sed -n 's/^LECBH_VERSION="\(.*\)"$/\1/p' lib/core.sh)
[[ -n $EXPECTED_VERSION ]] || { echo "Cannot read LECBH_VERSION from lib/core.sh" >&2; exit 1; }

passed=0
failed=0
failed_names=()

# shellcheck disable=SC2329 # invoked via trap
cleanup() {
    echo -e "${YELLOW}Cleaning up Docker container...${NC}"
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_container() {
    "${COMPOSE[@]}" exec -T -e EXPECTED_VERSION="$EXPECTED_VERSION" lecbh-test \
        bash -o pipefail -c "$1"
}

record() {
    if [[ $1 -eq 0 ]]; then
        echo -e "${GREEN}✓ ${2}${NC}"
        passed=$((passed + 1))
    else
        echo -e "${RED}✗ ${2}${NC}"
        failed=$((failed + 1))
        failed_names+=("$2")
    fi
}

# expect_pass NAME CMD: CMD must exit 0.
expect_pass() {
    local name=$1 cmd=$2 output
    echo -e "${YELLOW}▶ ${name}${NC}"
    if output=$(in_container "$cmd" 2>&1); then
        record 0 "$name"
    else
        echo "$output" | tail -20
        record 1 "$name"
    fi
}

# expect_fail NAME PATTERN CMD: CMD must exit non-zero AND its output must match PATTERN,
# so that unrelated crashes are not mistaken for the intended validation failure.
expect_fail() {
    local name=$1 pattern=$2 cmd=$3 output
    echo -e "${YELLOW}▶ ${name} (expecting failure)${NC}"
    if output=$(in_container "$cmd" 2>&1); then
        echo "  command unexpectedly succeeded"
        echo "$output" | tail -20
        record 1 "$name"
    elif grep -qE -- "$pattern" <<<"$output"; then
        record 0 "$name"
    else
        echo "  command failed, but output did not match: $pattern"
        echo "$output" | tail -20
        record 1 "$name"
    fi
}

echo -e "${YELLOW}Building and starting test container...${NC}"
"${COMPOSE[@]}" up -d --build --wait || { echo -e "${RED}Container failed to start${NC}"; exit 1; }

LECBH="/app/lecbh.sh"
MOCK="--unattended --test-mode"

echo -e "${YELLOW}==== Basic behaviour (mock certbot) ====${NC}"
expect_pass "Help command" "$LECBH --help | grep 'Usage:' >/dev/null"
expect_pass "Dry run with Apache" "$LECBH --dry-run $MOCK --server=apache"
expect_pass "Dry run with Nginx" "$LECBH --dry-run $MOCK --server=nginx"
expect_pass "Verbose output" "$LECBH --dry-run --verbose $MOCK --server=apache"
expect_pass "Staging flag is forwarded" \
    "$LECBH --dry-run --staging $MOCK --server=apache 2>&1 | grep -- '--staging' >/dev/null"
expect_pass "Multiple domains are forwarded" \
    "$LECBH --dry-run $MOCK --server=apache --domains=example.com,www.example.com 2>&1 | grep -- '-d example.com -d www.example.com' >/dev/null"
expect_pass "Dry run uses certonly with --dry-run" \
    "$LECBH --dry-run $MOCK --server=apache --domains=example.com 2>&1 | grep -E '\[lecbh mock certbot\] certonly .*--dry-run' >/dev/null"
expect_pass "Omitted email is not passed to certbot" \
    "! $LECBH --dry-run $MOCK --server=apache --domains=example.com 2>&1 | grep -- '--email' >/dev/null"

echo -e "${YELLOW}==== Commands ====${NC}"
expect_pass "version prints the semver" "[ \"\$($LECBH version)\" = \"\$EXPECTED_VERSION\" ]"
expect_pass "--version matches version" "[ \"\$($LECBH --version)\" = \"\$EXPECTED_VERSION\" ]"
expect_pass "version --json" \
    "$LECBH version --json | jq -e --arg v \"\$EXPECTED_VERSION\" '. == {version: \$v}' >/dev/null"
expect_pass "Explicit issue command" "$LECBH issue --dry-run $MOCK --server=apache --domains=example.com"
expect_fail "Unknown command is rejected" "Unknown command: frobnicate" "$LECBH frobnicate"

echo -e "${YELLOW}==== JSON output ====${NC}"
expect_pass "JSON output is valid and matches schema" "
    $LECBH --dry-run $MOCK --server=apache --domains=example.com,www.example.com --email=ops@example.org --json 2>/dev/null |
    jq -e --arg v \"\$EXPECTED_VERSION\" '
        (keys == ([\"domains\",\"dry_run\",\"email\",\"install_method\",\"redirect\",\"server\",\"staging\",\"test_mode\",\"timestamp\",\"version\"] | sort))
        and .domains == [\"example.com\",\"www.example.com\"]
        and .email == \"ops@example.org\"
        and .server == \"apache\"
        and .install_method == \"snap\"
        and .dry_run == true and .staging == false and .test_mode == true and .redirect == true
        and (.timestamp | test(\"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$\"))
        and .version == \$v
    ' >/dev/null"
expect_pass "JSON reflects --no-redirect, --staging and nginx" "
    $LECBH --dry-run --staging --no-redirect $MOCK --server=nginx --domains=example.com --json 2>/dev/null |
    jq -e '.redirect == false and .staging == true and .server == \"nginx\" and .email == \"\"' >/dev/null"
expect_pass "JSON stdout is empty on failure" "
    out=\$($LECBH $MOCK --domains=bad_domain --json 2>/dev/null); rc=\$?; [ \$rc -ne 0 ] && [ -z \"\$out\" ]"

echo -e "${YELLOW}==== Input validation ====${NC}"
expect_fail "Invalid domain is rejected" "Invalid domain: bad_domain" \
    "$LECBH --dry-run $MOCK --server=apache --domains=bad_domain"
expect_fail "IP address is rejected as a domain" "Invalid domain: 192.0.2.1" \
    "$LECBH --dry-run $MOCK --server=apache --domains=192.0.2.1"
expect_fail "Invalid email is rejected" "Invalid email: not-an-email" \
    "$LECBH --dry-run $MOCK --server=apache --domains=example.com --email=not-an-email"
expect_fail "Wildcard domain is rejected" "require DNS-01" \
    "$LECBH --dry-run $MOCK --server=apache --domains='*.example.com'"
expect_fail "Unknown server is rejected" "Unsupported server: caddy" \
    "$LECBH --dry-run $MOCK --server=caddy --domains=example.com"
expect_fail "Unknown option is rejected" "Unknown option: --bogus" \
    "$LECBH --bogus"

echo -e "${YELLOW}==== Concurrency lock ====${NC}"
expect_pass "Second concurrent run is refused" "
    LECBH_SLEEP_BEFORE_EXIT=3 $LECBH --dry-run $MOCK --server=apache --domains=example.com >/tmp/first.log 2>&1 &
    first=\$!
    sleep 1
    if $LECBH --dry-run $MOCK --server=apache --domains=example.com >/tmp/second.log 2>&1; then exit 1; fi
    grep -q 'Another lecbh instance is running' /tmp/second.log && wait \$first"
expect_pass "Lock is released after exit" \
    "$LECBH --dry-run $MOCK --server=apache --domains=example.com"

echo -e "${YELLOW}==== Installer paths ====${NC}"
# Must run before the pip install below, which places a real certbot on PATH.
expect_fail "Snap install fails cleanly without snapd" "snap command not found" \
    "$LECBH --dry-run --unattended --snap --server=apache --domains=example.com"
expect_pass "Pip installs certbot into /opt/certbot venv" "
    LECBH_TEST_INSTALL=1 $LECBH --dry-run --staging $MOCK --pip --server=nginx --domains=example.com &&
    /opt/certbot/bin/certbot --version &&
    [ \"\$(readlink -f /usr/bin/certbot)\" = \"\$(readlink -f /opt/certbot/bin/certbot)\" ] &&
    /opt/certbot/bin/certbot plugins --text 2>/dev/null | grep '^\* nginx' >/dev/null"

echo
echo -e "${YELLOW}Test summary: ${passed} passed, ${failed} failed${NC}"
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
printf "${RED}  - %s${NC}\n" "${failed_names[@]}"
exit 1
