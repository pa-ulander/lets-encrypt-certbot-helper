#!/usr/bin/env bats
# Flag parsing tests for lecbh_parse_flags (lib/core.sh).

load test_helper

setup() {
    load_core
    unset DEFAULT_INSTALL_METHOD
    lecbh_reset_options
}

@test "defaults" {
    lecbh_parse_flags
    [ "$DRY_RUN" = false ]
    [ "$UNATTENDED" = false ]
    [ "$VERBOSE" = false ]
    [ "$QUIET" = false ]
    [ "$STAGING" = false ]
    [ "$TEST_MODE" = false ]
    [ "$NO_REDIRECT" = false ]
    [ "$JSON_MODE" = false ]
    [ "$SHOW_HELP" = false ]
    [ "$SHOW_VERSION" = false ]
    [ "$INSTALL_METHOD" = snap ]
    [ -z "$SERVER" ]
    [ -z "$EMAIL_OVERRIDE" ]
    [ -z "$DOMAINS_OVERRIDE" ]
}

@test "DEFAULT_INSTALL_METHOD seeds install method" {
    DEFAULT_INSTALL_METHOD=pip lecbh_reset_options
    [ "$INSTALL_METHOD" = pip ]
}

@test "boolean flags" {
    lecbh_parse_flags --dry-run --unattended --staging --test-mode --no-redirect
    [ "$DRY_RUN" = true ]
    [ "$UNATTENDED" = true ]
    [ "$STAGING" = true ]
    [ "$TEST_MODE" = true ]
    [ "$NO_REDIRECT" = true ]
}

@test "value flags" {
    lecbh_parse_flags --server=nginx --email=a@example.org --domains=example.com,www.example.com
    [ "$SERVER" = nginx ]
    [ "$EMAIL_OVERRIDE" = a@example.org ]
    [ "$DOMAINS_OVERRIDE" = example.com,www.example.com ]
}

@test "value flags keep '=' inside values" {
    lecbh_parse_flags "--email=a=b@example.org"
    [ "$EMAIL_OVERRIDE" = "a=b@example.org" ]
}

@test "install method: last flag wins" {
    lecbh_parse_flags --pip
    [ "$INSTALL_METHOD" = pip ]
    lecbh_parse_flags --pip --snap
    [ "$INSTALL_METHOD" = snap ]
}

@test "verbose and quiet: quiet wins regardless of order" {
    lecbh_parse_flags --verbose --quiet
    [ "$QUIET" = true ]
    [ "$VERBOSE" = false ]
    lecbh_reset_options
    lecbh_parse_flags --quiet --verbose
    [ "$QUIET" = true ]
    [ "$VERBOSE" = false ]
}

@test "--json implies quiet" {
    lecbh_parse_flags --verbose --json
    [ "$JSON_MODE" = true ]
    [ "$QUIET" = true ]
    [ "$VERBOSE" = false ]
}

@test "--help and -h" {
    lecbh_parse_flags --help
    [ "$SHOW_HELP" = true ]
    lecbh_reset_options
    lecbh_parse_flags -h
    [ "$SHOW_HELP" = true ]
}

@test "--version" {
    lecbh_parse_flags --version
    [ "$SHOW_VERSION" = true ]
}

@test "unknown option fails with a message" {
    run lecbh_parse_flags --dry-run --bogus
    [ "$status" -eq 1 ]
    lecbh_parse_flags --bogus || true
    [ "$LECBH_ERROR" = "Unknown option: --bogus (use --help)" ]
}

@test "value flag without '=' is unknown" {
    refute lecbh_parse_flags --email admin@example.org
    [[ $LECBH_ERROR == *"--email"* ]]
}

@test "reset clears previous state" {
    lecbh_parse_flags --dry-run --json --server=nginx
    lecbh_reset_options
    [ "$DRY_RUN" = false ]
    [ "$JSON_MODE" = false ]
    [ -z "$SERVER" ]
}
