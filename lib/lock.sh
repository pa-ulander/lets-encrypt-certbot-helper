# shellcheck shell=bash
# lecbh concurrency lock. The lock is held on file descriptor 9 until the process exits,
# so it is released automatically even if lecbh is killed.
# Returns 0 on success, 1 if another process holds it, 2 if flock is missing,
# 3 if the lock file cannot be opened.
lecbh_acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 2
    { exec 9>"$1"; } 2>/dev/null || return 3
    flock -n 9 || return 1
}
