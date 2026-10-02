#!/usr/bin/env bash
# Start waybar, and confirm it actually appeared
# A waybar process can be running while having failed to register its layer-shell
# surface - a silent early-session display race. So this checks that Hyprland
# registered a waybar layer, and clears a surface-less zombie between retries.

set -uo pipefail

# --restart: kill any existing waybar first, then start, so it re-reads colors.css.
# Routed through this script because a bare kill-and-forget restart can land in the
# not-ready display window and leave the bar gone for the session with nothing checking.
RESTART=false
for arg in "$@"; do
    case "$arg" in
        --restart) RESTART=true ;;
        -h|--help)
            printf 'Usage: %s [--restart]\n' "${0##*/}"
            printf '  (no args)  start waybar if it is not already healthy\n'
            printf '  --restart  kill any existing waybar, then start it (use after a theme change)\n'
            exit 0
            ;;
        *)
            printf '[ensure-waybar] unknown option: %s\n' "$arg" >&2
            exit 1
            ;;
    esac
done

LOG_FILE="${HYPRX_LOGGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}/hyprx.log"

log() {
    printf '[ensure-waybar] %s\n' "$*" >&2
    printf '[%s] [INFO] ensure-waybar: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

command -v waybar >/dev/null 2>&1 || {
    log "waybar not installed - nothing to start"
    exit 1
}

# Hyprland's IPC has to answer before a layer can exist.
wait_for_hyprland() {
    local i
    for ((i = 0; i < 50; i++)); do
        if hyprctl layers >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Checks the compositor registered the surface, not just that the process exists.
waybar_healthy() {
    pgrep -x waybar >/dev/null 2>&1 || return 1
    hyprctl layers 2>/dev/null | grep -q "namespace: waybar"
}

# A waybar with no surface. Left in place it makes every later
# `pgrep` check pass while the bar is still invisible.
waybar_is_stuck() {
    pgrep -x waybar >/dev/null 2>&1 || return 1
    ! hyprctl layers 2>/dev/null | grep -q "namespace: waybar"
}

if ! wait_for_hyprland; then
    log "Hyprland IPC never became ready - cannot start waybar"
    exit 1
fi

if $RESTART; then
    if pgrep -x waybar >/dev/null 2>&1; then
        log "--restart: killing existing waybar so it re-reads its config"
        pkill -x waybar >/dev/null 2>&1 || true
        # Wait for the old surface to go away, else the health check below can see
        # the outgoing waybar's layer and call it healthy before the replacement.
        restart_wait=0
        while (( restart_wait < 20 )) && pgrep -x waybar >/dev/null 2>&1; do
            sleep 0.25
            restart_wait=$((restart_wait + 1))
        done
        sleep 0.5
    fi
fi

# Already healthy (e.g. re-running after a reload) - leave it alone.
if waybar_healthy; then
    log "waybar already running with a registered surface"
    exit 0
fi

log "no healthy waybar - starting"

# Generous window: delays back off then settle at 4s, so with the 4s inner health
# wait this totals a little over two minutes - long enough to outlast a slow
# hybrid-GPU init, short enough to report a real failure while you are watching.
attempt=0
waited=0
restart_wait=0
for delay in 1 1 2 2 3 3 4 4 4 4 4 4 4 4 4 4; do
    attempt=$((attempt + 1))

    if waybar_is_stuck; then
        log "attempt $attempt: found a waybar with no surface - clearing it"
        pkill -x waybar >/dev/null 2>&1 || true
        sleep 0.5
    fi

    if ! pgrep -x waybar >/dev/null 2>&1; then
        log "attempt $attempt: launching waybar"
        waybar >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi

    # Waybar registers its surface within a second or two or not at all, so a short
    # inner wait is right - the long budget comes from the outer schedule.
    waited=0
    while (( waited < 4 )); do
        sleep 1
        waited=$((waited + 1))
        if waybar_healthy; then
            log "waybar is up with a registered surface (attempt $attempt)"
            exit 0
        fi
    done

    log "attempt $attempt: no surface yet - retrying in ${delay}s"
    sleep "$delay"
done

log "FAILED - waybar never registered a surface after $attempt attempts"
log "check: waybar -c ~/.config/waybar/config.jsonc   (run it in a terminal to see the error)"
exit 1
