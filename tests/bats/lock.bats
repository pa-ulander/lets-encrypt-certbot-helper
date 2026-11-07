#!/usr/bin/env bats
# Lock acquisition tests for lib/lock.sh.

load test_helper

setup() {
    load_lock
    command -v flock >/dev/null 2>&1 || skip "flock not installed"
    LOCK="$BATS_TEST_TMPDIR/lecbh.lock"
}

@test "acquires a free lock" {
    run bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK"
    [ "$status" -eq 0 ]
    [ -e "$LOCK" ]
}

@test "refuses while another process holds the lock" {
    flock "$LOCK" sleep 5 &
    local holder=$!
    # Wait until the holder has the lock.
    for _ in $(seq 50); do
        if ! flock -n "$LOCK" true; then break; fi
        sleep 0.1
    done
    run bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK"
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [ "$status" -eq 1 ]
}

@test "lock is released when the holding process exits" {
    run bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK"
    [ "$status" -eq 0 ]
    run bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK"
    [ "$status" -eq 0 ]
}

@test "second acquire in a concurrent process fails while first is alive" {
    bash -c 'source "$1"; lecbh_acquire_lock "$2" && sleep 5' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK" &
    local holder=$!
    for _ in $(seq 50); do
        if ! flock -n "$LOCK" true; then break; fi
        sleep 0.1
    done
    run bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK"
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [ "$status" -eq 1 ]
}

@test "returns 3 when the lock file cannot be opened" {
    run bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$BATS_TEST_TMPDIR/missing-dir/lecbh.lock"
    [ "$status" -eq 3 ]
}

@test "returns 2 when flock is unavailable" {
    # shellcheck disable=SC2016 # expanded by the inner shell
    run env PATH=/nonexistent /bin/bash -c 'source "$1"; lecbh_acquire_lock "$2"' _ "$LECBH_ROOT/lib/lock.sh" "$LOCK"
    [ "$status" -eq 2 ]
}
