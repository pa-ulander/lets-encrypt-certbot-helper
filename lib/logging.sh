# shellcheck shell=bash disable=SC2034 # COLOR_* markers are used by lecbh.sh
# lecbh logging. All messages go to stderr so stdout stays reserved for results (e.g. --json).
# Reads VERBOSE and QUIET; set LECBH_NO_COLOR=1 for plain-text markers.

if [[ ${LECBH_NO_COLOR:-0} == 1 ]]; then
    COLOR_OK="[OK]"; COLOR_WARN="[WARN]"; COLOR_ERR="[ERR]"; COLOR_INFO="[INFO]"; COLOR_KEY="[LECBH]"
else
    COLOR_OK="✅"; COLOR_WARN="⚠️"; COLOR_ERR="❌"; COLOR_INFO="🔍"; COLOR_KEY="🔐"
fi

log() { if ${VERBOSE:-false} && ! ${QUIET:-false}; then echo "${COLOR_INFO} $*" >&2; fi; return 0; }
info() { if ! ${QUIET:-false}; then echo "$*" >&2; fi; return 0; }
warn() { echo "${COLOR_WARN} $*" >&2; return 0; }
die() { echo "${COLOR_ERR} $*" >&2; exit 1; }
