#!/usr/bin/env bats
# Unit tests for the pure functions in lib/core.sh.

load test_helper

setup() {
    load_core
}

@test "version is semver" {
    [[ $LECBH_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "email: accepts valid addresses" {
    lecbh_is_valid_email admin@example.org
    lecbh_is_valid_email first.last+tag@sub.example.co.uk
}

@test "email: rejects invalid addresses" {
    refute lecbh_is_valid_email ""
    refute lecbh_is_valid_email admin
    refute lecbh_is_valid_email admin@localhost
    refute lecbh_is_valid_email "a b@example.org"
    refute lecbh_is_valid_email admin@@example.org
}

@test "domain: accepts valid hostnames" {
    lecbh_is_valid_domain example.com
    lecbh_is_valid_domain www.example.com
    lecbh_is_valid_domain xn--bcher-kva.example
    lecbh_is_valid_domain a-b.c0.example.org
    lecbh_is_valid_domain 1.example.com
}

@test "domain: rejects single labels, IPs and malformed names" {
    refute lecbh_is_valid_domain ""
    refute lecbh_is_valid_domain localhost
    refute lecbh_is_valid_domain 192.168.1.1
    refute lecbh_is_valid_domain example..com
    refute lecbh_is_valid_domain .example.com
    refute lecbh_is_valid_domain example.com.
    refute lecbh_is_valid_domain -example.com
    refute lecbh_is_valid_domain example-.com
    refute lecbh_is_valid_domain "exa mple.com"
    refute lecbh_is_valid_domain "example.com;rm"
    refute lecbh_is_valid_domain "*.example.com"
}

@test "domain: enforces label and total length limits" {
    local l63 l64
    l63=$(printf 'a%.0s' {1..63})
    l64=$(printf 'a%.0s' {1..64})
    lecbh_is_valid_domain "$l63.com"
    refute lecbh_is_valid_domain "$l64.com"
    # 4 x 63 chars + 3 dots = 255 > 253
    refute lecbh_is_valid_domain "$l63.$l63.$l63.$l63"
}

@test "wildcard detection" {
    lecbh_is_wildcard_domain "*.example.com"
    lecbh_is_wildcard_domain "foo.*.example.com"
    refute lecbh_is_wildcard_domain example.com
}

@test "server and install method validation" {
    lecbh_is_valid_server apache
    lecbh_is_valid_server nginx
    refute lecbh_is_valid_server caddy
    refute lecbh_is_valid_server ""
    lecbh_is_valid_install_method snap
    lecbh_is_valid_install_method pip
    refute lecbh_is_valid_install_method apt
}

@test "split_domains trims whitespace and drops empty items" {
    run lecbh_split_domains " example.com , www.example.com,,  api.example.com  ,"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = example.com ]
    [ "${lines[1]}" = www.example.com ]
    [ "${lines[2]}" = api.example.com ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "split_domains does not glob-expand" {
    cd "$BATS_TEST_TMPDIR"
    touch a.example.com b.example.com
    run lecbh_split_domains "*.example.com"
    [ "$output" = "*.example.com" ]
}

@test "split_domains returns nothing for empty input" {
    run lecbh_split_domains " , ,"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "certbot args: real unattended run obtains and installs with redirect" {
    result=$(lecbh_certbot_args apache admin@example.org false false false true true example.com www.example.com | joined)
    [ "$result" = "certbot --apache -d example.com -d www.example.com --email admin@example.org --agree-tos --non-interactive --redirect" ]
}

@test "certbot args: dry run uses certonly, never --redirect" {
    result=$(lecbh_certbot_args nginx "" true false true true false example.com | joined)
    [ "$result" = "certbot certonly --nginx -d example.com --dry-run --staging" ]
}

@test "certbot args: test mode uses certonly, never --redirect" {
    result=$(lecbh_certbot_args apache "" false true false true true example.com | joined)
    [ "$result" = "certbot certonly --apache -d example.com --agree-tos --non-interactive" ]
}

@test "certbot args: no email means no --email flag" {
    result=$(lecbh_certbot_args apache "" false false false false true example.com | joined)
    [[ $result != *--email* ]]
    [[ $result != *--redirect* ]]
}

@test "certbot args: one argument per line keeps values intact" {
    mapfile -t args < <(lecbh_certbot_args apache "a@example.org" false false false false false "example.com")
    [ "${args[0]}" = certbot ]
    [ "${args[1]}" = --apache ]
    [ "${args[2]}" = -d ]
    [ "${args[3]}" = example.com ]
    [ "${args[4]}" = --email ]
    [ "${args[5]}" = a@example.org ]
    [ "${#args[@]}" -eq 6 ]
}

@test "json_string escapes quotes, backslashes and control characters" {
    run lecbh_json_string "$(printf 'a"b\\c\nd\te\001f')"
    [ "$output" = '"a\"b\\c\nd\te\u0001f"' ]
}

@test "json_string output round-trips through jq" {
    require_jq
    local input
    input=$(printf 'q"uote\\back\tslash\001\037 ünïcode')
    result=$(lecbh_json_string "$input" | jq -r .)
    [ "$result" = "$input" ]
}

@test "json_array and json_bool" {
    [ "$(lecbh_json_array)" = "[]" ]
    [ "$(lecbh_json_array a 'b"c')" = '["a","b\"c"]' ]
    [ "$(lecbh_json_bool true)" = true ]
    [ "$(lecbh_json_bool false)" = false ]
    [ "$(lecbh_json_bool yes)" = false ]
}

@test "result_json has the documented keys in order" {
    require_jq
    json=$(lecbh_result_json "" nginx pip true true false false 2025-01-02T03:04:05Z example.com www.example.com)
    keys=$(jq -c 'keys_unsorted' <<<"$json")
    [ "$keys" = '["domains","email","server","install_method","dry_run","staging","test_mode","redirect","timestamp","version"]' ]
    jq -e --arg v "$LECBH_VERSION" '
        .domains == ["example.com","www.example.com"] and .email == "" and
        .server == "nginx" and .install_method == "pip" and
        .dry_run == true and .staging == true and .test_mode == false and
        .redirect == false and .timestamp == "2025-01-02T03:04:05Z" and .version == $v
    ' <<<"$json"
}

@test "result_json escapes hostile values" {
    require_jq
    json=$(lecbh_result_json 'x"y@example.org' apache snap false false true true now 'ex"ample.com')
    [ "$(jq -r .email <<<"$json")" = 'x"y@example.org' ]
    [ "$(jq -r '.domains[0]' <<<"$json")" = 'ex"ample.com' ]
}

@test "version_json" {
    [ "$(lecbh_version_json)" = "{\"version\": \"$LECBH_VERSION\"}" ]
}
