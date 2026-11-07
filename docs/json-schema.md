# JSON Output Schema (v0)

## Issue result (`lecbh issue --json`)

Required keys, always emitted in this order:
- domains: string[]
- email: string
- server: "apache" | "nginx"
- install_method: "snap" | "pip"
- dry_run: bool
- staging: bool
- test_mode: bool
- redirect: bool
- timestamp: RFC3339 UTC
- version: semver

When no account email is configured, `email` is an empty string. On success, `--json` writes only this object to stdout; progress and errors go to stderr. Failed runs exit non-zero and do not emit a success object.

## Version (`lecbh version --json`)

```json
{"version": "1.2.0"}
```

- version: semver

## Stability

Key names, types and order are covered by the Bats tests (`tests/bats/core.bats`) and the container suite (`test.sh`). Any change must update this document and those tests.

## Future (not yet implemented)
- challenge_type
- log_id