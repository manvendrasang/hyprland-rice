#!/usr/bin/env bash

# Privilege elevation for non-interactive frontends (GUI prerequisite #4).
#
# The install gate probes sudo with `sudo -n true` (no prompt) and falls back
# to `sudo -v` (prompts on a TTY). A GUI has no TTY, so neither works: the
# first fails and the second hangs or dies on EOF. `hyprx ... --password-stdin`
# closes the gap: the frontend prompts for the password with its own native
# dialog and pipes it in. The CLI validates it once, caches the credential,
# and keeps it warm for the whole run.
#
# SECURITY CONTRACT - read before touching this file:
# - The password travels stdin pipe -> one shell variable -> `sudo -S`, and
#   is unset immediately after validation. It never appears in argv, the
#   environment, a file, or any log. The suite asserts this with a canary.
# - The credential refresher runs `sudo -n -v` (non-interactive, uses the
#   cached ticket, never prompts) every 45s so a long AUR build cannot hit a
#   mid-run password prompt on a stdin that has nothing left to give.
# - The refresher dies with the main process (EXIT trap, same-subshell guard
#   as the lock - see lib/lock.sh) and the EXIT trap is the ONLY owner of
#   both cleanups, so neither can be orphaned or double-run.
# - Callers must not rely on interactive confirmations in the same run: stdin
#   is consumed by the password, and anything reading past it gets EOF. GUI
#   flow is preview first (`--dry-run`, whose events carry mode=dry-run),
#   confirm in the GUI, then run with HYPRX_CONFIG_AUTO_CONFIRM=true.
#
# `--password-stdin` is a GUI-only flag. On a TTY the password is read silently
# with echo off; from a pipe exactly one line is read. Empty input is refused.

HYPRX_ELEVATE_REFRESH_PID=""

hyprx_elevate_cleanup() {
    (( BASH_SUBSHELL == 0 )) || return 0

    if [[ -n "$HYPRX_ELEVATE_REFRESH_PID" ]] && kill -0 "$HYPRX_ELEVATE_REFRESH_PID" 2>/dev/null; then
        kill "$HYPRX_ELEVATE_REFRESH_PID" 2>/dev/null || true
    fi
    HYPRX_ELEVATE_REFRESH_PID=""

    # The lock release lives on the same trap so the two cleanups cannot be
    # separated: a process that held sudo warm and a lock must drop both.
    hyprx_lock_release
    return 0
}

hyprx_elevate_password_stdin() {
    local password=""

    if [[ -t 0 ]]; then
        IFS= read -rs password || true
        echo >&2
    else
        IFS= read -r password || true
    fi

    if [[ -z "$password" ]]; then
        hyprx_ui_error "No password provided on stdin (--password-stdin needs one line)."
        hyprx_event auth.failed reason="empty-input"
        return 1
    fi

    # The password exists in this variable for exactly the next statement.
    if printf '%s\n' "$password" | sudo -S -v 2>/dev/null; then
        password=""
        unset password
        hyprx_event auth.ok
    else
        password=""
        unset password
        hyprx_ui_error "sudo rejected the password."
        hyprx_event auth.failed reason="rejected"
        return 1
    fi

    # Keep the ticket warm for the whole run. The loop's parent check is
    # belt-and-braces; the EXIT trap is what actually reaps it. The iteration
    # cap bounds a runaway if the parent PID gets reused after a SIGKILL.
    # HYPRX_ELEVATE_REFRESH_EVERY overrides the interval (the suite sets 1s
    # to observe the refresher without waiting out the production 45s).
    # The first refresh fires immediately rather than after one interval, so
    # even a sub-second command proves the refresher lived (the suite asserts
    # exactly that) and a ticket that died between validation and start is
    # caught before any privileged step runs.
    (
        i=0
        while kill -0 $$ 2>/dev/null && (( i < 160 )); do
            sudo -n -v >/dev/null 2>&1 || true
            sleep "${HYPRX_ELEVATE_REFRESH_EVERY:-45}"
            i=$((i + 1))
        done
    ) & disown 2>/dev/null || true
    HYPRX_ELEVATE_REFRESH_PID="$!"

    return 0
}
