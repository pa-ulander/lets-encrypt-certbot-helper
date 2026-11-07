# shellcheck shell=bash disable=SC2034 # option globals are consumed by lecbh.sh
# lecbh core: pure functions. They only read their arguments and write to stdout,
# except lecbh_reset_options/lecbh_parse_flags, which set the option globals below.

LECBH_VERSION="1.2.0"

lecbh_reset_options() {
    DRY_RUN=false
    UNATTENDED=false
    VERBOSE=false
    QUIET=false
    STAGING=false
    TEST_MODE=false
    NO_REDIRECT=false
    JSON_MODE=false
    SHOW_HELP=false
    SHOW_VERSION=false
    INSTALL_METHOD=${DEFAULT_INSTALL_METHOD:-snap}
    SERVER=""
    EMAIL_OVERRIDE=""
    DOMAINS_OVERRIDE=""
    LECBH_ERROR=""
}

# Returns 1 and sets LECBH_ERROR on an unknown option.
lecbh_parse_flags() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true ;;
            --unattended) UNATTENDED=true ;;
            --verbose) $QUIET || VERBOSE=true ;;
            --quiet) QUIET=true; VERBOSE=false ;;
            --staging) STAGING=true ;;
            --test-mode) TEST_MODE=true ;;
            --pip) INSTALL_METHOD=pip ;;
            --snap) INSTALL_METHOD=snap ;;
            --server=*) SERVER=${1#*=} ;;
            --email=*) EMAIL_OVERRIDE=${1#*=} ;;
            --domains=*) DOMAINS_OVERRIDE=${1#*=} ;;
            --no-redirect) NO_REDIRECT=true ;;
            --json) JSON_MODE=true; QUIET=true; VERBOSE=false ;;
            --help | -h) SHOW_HELP=true ;;
            --version) SHOW_VERSION=true ;;
            *)
                LECBH_ERROR="Unknown option: $1 (use --help)"
                return 1
                ;;
        esac
        shift
    done
}

lecbh_is_valid_email() {
    [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]
}

lecbh_is_wildcard_domain() {
    [[ $1 == *'*'* ]]
}

# RFC 1123 hostname: dot-separated labels of 1-63 alphanumerics/hyphens that neither
# start nor end with a hyphen, total length <= 253, and a final label containing a
# letter (rejects bare IP addresses).
lecbh_is_valid_domain() {
    local label='[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    [[ ${#1} -le 253 && $1 =~ ^($label\.)+$label$ && ${1##*.} == *[A-Za-z]* ]]
}

lecbh_is_valid_server() {
    [[ $1 == apache || $1 == nginx ]]
}

lecbh_is_valid_install_method() {
    [[ $1 == snap || $1 == pip ]]
}

# Splits a comma-separated list, trims whitespace, drops empty items. One item per line.
lecbh_split_domains() {
    local IFS=',' item
    local -a parts=()
    read -r -a parts <<<"$1" || true
    for item in "${parts[@]}"; do
        item=${item#"${item%%[![:space:]]*}"}
        item=${item%"${item##*[![:space:]]}"}
        if [[ -n $item ]]; then printf '%s\n' "$item"; fi
    done
}

# Prints the certbot argv, one argument per line.
# Usage: lecbh_certbot_args SERVER EMAIL DRY_RUN TEST_MODE STAGING REDIRECT UNATTENDED DOMAIN...
# Real runs use certbot's default "run" (obtain + install); --dry-run only works with certonly.
lecbh_certbot_args() {
    local server=$1 email=$2 dry_run=$3 test_mode=$4 staging=$5 redirect=$6 unattended=$7 d
    shift 7
    printf '%s\n' certbot
    if [[ $dry_run == true || $test_mode == true ]]; then printf '%s\n' certonly; fi
    printf '%s\n' "--$server"
    for d in "$@"; do printf '%s\n' -d "$d"; done
    if [[ -n $email ]]; then printf '%s\n' --email "$email"; fi
    if [[ $unattended == true ]]; then printf '%s\n' --agree-tos --non-interactive; fi
    if [[ $dry_run == true ]]; then printf '%s\n' --dry-run; fi
    if [[ $staging == true ]]; then printf '%s\n' --staging; fi
    if [[ $redirect == true && $dry_run != true && $test_mode != true ]]; then printf '%s\n' --redirect; fi
}

lecbh_json_string() {
    local s=$1 i c
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    for ((i = 1; i < 32; i++)); do
        printf -v c '%b' "\\0$(printf '%03o' "$i")"
        if [[ $s == *"$c"* ]]; then s=${s//"$c"/$(printf '\\u%04x' "$i")}; fi
    done
    printf '"%s"' "$s"
}

lecbh_json_array() {
    local out="[" sep="" item
    for item in "$@"; do
        out+="$sep$(lecbh_json_string "$item")"
        sep=","
    done
    printf '%s]' "$out"
}

lecbh_json_bool() {
    if [[ $1 == true ]]; then printf 'true'; else printf 'false'; fi
}

# Field order is part of the documented schema (docs/json-schema.md).
# Usage: lecbh_result_json EMAIL SERVER METHOD DRY_RUN STAGING TEST_MODE REDIRECT TIMESTAMP DOMAIN...
lecbh_result_json() {
    local email=$1 server=$2 method=$3 dry_run=$4 staging=$5 test_mode=$6 redirect=$7 timestamp=$8
    shift 8
    cat <<EOF
{
  "domains": $(lecbh_json_array "$@"),
  "email": $(lecbh_json_string "$email"),
  "server": $(lecbh_json_string "$server"),
  "install_method": $(lecbh_json_string "$method"),
  "dry_run": $(lecbh_json_bool "$dry_run"),
  "staging": $(lecbh_json_bool "$staging"),
  "test_mode": $(lecbh_json_bool "$test_mode"),
  "redirect": $(lecbh_json_bool "$redirect"),
  "timestamp": $(lecbh_json_string "$timestamp"),
  "version": $(lecbh_json_string "$LECBH_VERSION")
}
EOF
}

lecbh_version_json() {
    printf '{"version": %s}\n' "$(lecbh_json_string "$LECBH_VERSION")"
}
