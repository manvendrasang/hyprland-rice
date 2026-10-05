#!/usr/bin/env bash

# Single-writer discipline (GUI prerequisite #3).
#
# install, rollback and clean all mutate shared state: install.state,
# snapshots, deployed configs. Two writers at once - two terminals, or the
# terminal plus a future GUI - corrupt all three. The lock is one global
# mutex, not per-command: install-while-rollback is exactly as dangerous as
# install-while-install.
#
# The lock is a directory (mkdir is atomic, unlike test-then-create on a
# file) holding the holder's PID. A holder that died without releasing leaves
# a stale lock, detected via kill -0 and broken with a warning - a dead
# process cannot be waited on, so waiting would hang forever.
#
# Exit code 3 means "another operation holds the lock". 1 is usage/validation
# and 2 is reserved by doctor's warning/error split; 3 is unused elsewhere.

HYPRX_LOCK_HELD=""

hyprx_lock_dir() {
    printf '%s' "${HYPRX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}/hyprx.lock"
}

# True when WE hold the lock (set by a successful acquire in this process).
hyprx_lock_held() {
    [[ "$HYPRX_LOCK_HELD" == "1" ]]
}

hyprx_lock_acquire() {
    local dir holder_pid started
    dir="$(hyprx_lock_dir)"

    if mkdir "$dir" 2>/dev/null; then
        printf '%s\n' "$$" >"$dir/pid" 2>/dev/null || true
        printf '%s\n' "$(date +%s)" >"$dir/started" 2>/dev/null || true
        HYPRX_LOCK_HELD="1"
        return 0
    fi

    holder_pid="$(cat "$dir/pid" 2>/dev/null || true)"
    started="$(cat "$dir/started" 2>/dev/null || true)"

    if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
        hyprx_ui_warn "Breaking stale lock from dead process $holder_pid - it cannot release it."
        hyprx_event lock.stale pid="$holder_pid"
        rm -rf "$dir" 2>/dev/null || true
        if mkdir "$dir" 2>/dev/null; then
            printf '%s\n' "$$" >"$dir/pid" 2>/dev/null || true
            printf '%s\n' "$(date +%s)" >"$dir/started" 2>/dev/null || true
            HYPRX_LOCK_HELD="1"
            return 0
        fi
    fi

    local since=""
    [[ -n "$started" ]] && since=" (since $(date -d "@$started" '+%H:%M:%S' 2>/dev/null || echo "$started"))"
    hyprx_ui_error "Another HyprX operation is already running (pid ${holder_pid:-unknown}$since)."
    hyprx_ui_info "Wait for it to finish, or remove $(hyprx_lock_dir) if that process is gone."
    hyprx_event lock.busy pid="${holder_pid:-unknown}"
    return 3
}

hyprx_lock_release() {
    # EXIT traps also fire in command substitutions and subshells, where $$
    # is still the parent's PID - without this guard the first $(...) after
    # acquiring would release the lock out from under the main shell.
    (( BASH_SUBSHELL == 0 )) || return 0
    hyprx_lock_held || return 0

    local dir holder_pid
    dir="$(hyprx_lock_dir)"
    holder_pid="$(cat "$dir/pid" 2>/dev/null || true)"

    # Only remove what we own. A stale-break by another process replaced the
    # directory out from under us; deleting theirs would un-mutex them.
    if [[ "$holder_pid" == "$$" ]]; then
        rm -rf "$dir" 2>/dev/null || true
    fi
    HYPRX_LOCK_HELD=""
    return 0
}
