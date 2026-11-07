# shellcheck shell=bash disable=SC2034 # variables are used by the .bats files
# Shared setup for lecbh Bats tests.

LECBH_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
LECBH="$LECBH_ROOT/lecbh.sh"

load_core() {
    # shellcheck source=lib/core.sh
    source "$LECBH_ROOT/lib/core.sh"
}

load_lock() {
    # shellcheck source=lib/lock.sh
    source "$LECBH_ROOT/lib/lock.sh"
}

# Joins lines of output with single spaces for easy comparison.
joined() {
    tr '\n' ' ' | sed 's/ $//'
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# Asserts that a command fails. Use instead of a bare "! cmd", which does not fail
# a Bats test unless it is the last command.
refute() {
    if "$@"; then
        echo "expected failure: $*" >&2
        return 1
    fi
}
