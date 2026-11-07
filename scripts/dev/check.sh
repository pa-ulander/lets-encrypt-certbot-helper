#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

for tool in shellcheck bats jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[check] Required tool not found: $tool" >&2
        exit 1
    fi
done

echo "[check] ShellCheck"
shellcheck -x lecbh.sh lib/*.sh test.sh tests/bats/*.bats tests/bats/*.bash

echo "[check] Bats unit tests"
bats tests/bats

echo "[check] Integration tests"
./test.sh

echo "All checks passed"
