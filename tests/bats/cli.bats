#!/usr/bin/env bats
# CLI dispatcher tests for lecbh.sh. These never reach certbot: they cover commands
# that need no root, and early failures.

load test_helper

setup() {
    load_core
}

@test "version prints only the semver" {
    run "$LECBH" version
    [ "$status" -eq 0 ]
    [ "$output" = "$LECBH_VERSION" ]
}

@test "--version flag matches version command" {
    run "$LECBH" --version
    [ "$status" -eq 0 ]
    [ "$output" = "$LECBH_VERSION" ]
}

@test "version --json is valid JSON" {
    require_jq
    run "$LECBH" version --json
    [ "$status" -eq 0 ]
    [ "$(jq -r .version <<<"$output")" = "$LECBH_VERSION" ]
    [ "$(jq -c keys <<<"$output")" = '["version"]' ]
}

@test "help command and --help work without root" {
    run "$LECBH" help
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
    [[ $output == *"version"* ]]
    run "$LECBH" --help
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
    run "$LECBH" issue -h
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "unknown command fails" {
    run "$LECBH" frobnicate
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown command: frobnicate"* ]]
}

@test "unknown option fails" {
    run "$LECBH" --bogus
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown option: --bogus"* ]]
}

@test "issue requires root" {
    [ "$EUID" -ne 0 ] || skip "running as root"
    run "$LECBH" issue --unattended --test-mode
    [ "$status" -ne 0 ]
    [[ $output == *"Please run as root"* ]]
    run "$LECBH" --unattended --test-mode
    [ "$status" -ne 0 ]
    [[ $output == *"Please run as root"* ]]
}

@test "works when invoked through a symlink" {
    ln -s "$LECBH" "$BATS_TEST_TMPDIR/lecbh"
    run "$BATS_TEST_TMPDIR/lecbh" version
    [ "$status" -eq 0 ]
    [ "$output" = "$LECBH_VERSION" ]
}

@test "fails clearly when lib/ is missing" {
    cp "$LECBH" "$BATS_TEST_TMPDIR/lecbh.sh"
    run "$BATS_TEST_TMPDIR/lecbh.sh" version
    [ "$status" -ne 0 ]
    [[ $output == *"missing library"* ]]
}
