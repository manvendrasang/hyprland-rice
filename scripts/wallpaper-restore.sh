#!/usr/bin/env bash

# Startup wallpaper restore
#
# hyprpaper's IPC may not be ready the instant the process starts, and waypaper exits 0
# even when it set nothing, so every attempt is verified with `hyprctl hyprpaper listactive`.

set -uo pipefail

WALLPAPER_DIR="${HYPRX_WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
STATE_FILE="${HYPRX_WALLPAPER_STATE_OVERRIDE:-${HYPRX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}/last-wallpaper}"
WAYPAPER_CONFIG="${HYPRX_TARGET_HOME:-$HOME}/.config/waypaper/config.ini"
LOG_FILE="${HYPRX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}/hyprx.log"

log() {
    printf '[wallpaper-restore] %s\n' "$*" >&2
    printf '[%s] [INFO] wallpaper-restore: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

# A wallpaper is active if hyprpaper reports at least one target.
wallpaper_is_active() {
    local active
    active="$(hyprctl hyprpaper listactive 2>/dev/null || true)"
    [[ -n "${active//[[:space:]]/}" ]]
}

active_path() {
    hyprx_wallpaper_active
}

# Block until hyprpaper's IPC answers, or give up after ~10s.
wait_for_hyprpaper() {
    local i
    for ((i = 0; i < 50; i++)); do
        if hyprctl hyprpaper listactive >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Last-resort apply, bypassing waypaper: `hyprctl hyprpaper preload|reload|set` are all
# rejected by hyprpaper 0.8.x (only listactive is exposed), so write the conf and restart.
apply_direct() {
    local img="$1"
    local conf="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr/hyprpaper.conf"

    [[ -f "$img" ]] || return 1
    command -v hyprpaper >/dev/null 2>&1 || return 1

    mkdir -p "$(dirname "$conf")" 2>/dev/null || return 1

    cat >"$conf" <<EOF || return 1
wallpaper {
    monitor =
    path = $img
    fit_mode = cover
}

ipc = true
EOF

    pkill -x hyprpaper >/dev/null 2>&1 || true
    sleep 0.3
    hyprpaper >/dev/null 2>&1 &
    disown 2>/dev/null || true

    local i
    for ((i = 0; i < 25; i++)); do
        sleep 0.2
        if wallpaper_is_active; then
            return 0
        fi
    done

    return 1
}

remember() {
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || return 0
    printf '%s\n' "$1" >"$STATE_FILE" 2>/dev/null || true
}

remembered() {
    [[ -f "$STATE_FILE" ]] || return 1
    local p
    p="$(head -n1 "$STATE_FILE" 2>/dev/null || true)"
    [[ -n "$p" && -f "$p" ]] || return 1
    printf '%s' "$p"
}

# Keep hyprpaper.conf in step with what is on screen. Delegates to the shared
# helper (scripts/sync-hyprpaper-conf.sh) so it cannot drift from apply-wallust-theme.sh's copy.
SYNC_CONF="${HYPRX_TARGET_HOME:-$HOME}/.local/share/hyprx/scripts/sync-hyprpaper-conf.sh"

sync_conf() {
    [[ -x "$SYNC_CONF" ]] || return 0
    "$SYNC_CONF" "$1" || true
}

first_image() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.webp' -o -iname '*.bmp' \) 2>/dev/null | sort | head -n1
}

# Main

if ! command -v hyprctl >/dev/null 2>&1; then
    log "hyprctl not found - nothing to do"
    exit 0
fi

if ! wait_for_hyprpaper; then
    log "hyprpaper IPC never became ready - giving up"
    exit 0
fi

if wallpaper_is_active; then
    log "hyprpaper already has an active wallpaper: $(active_path)"
    remember "$(active_path)"
    sync_conf "$(active_path)"
    exit 0
fi

log "no active wallpaper - restoring"

# Attempt 1: waypaper, which honours the user's fill/monitor preferences (its
# --restore has nothing to restore until a wallpaper has been picked in the GUI).

if command -v waypaper >/dev/null 2>&1; then
    if [[ -f "$WAYPAPER_CONFIG" ]] \
       && grep -qE '^wallpaper[[:space:]]*=[[:space:]]*\S' "$WAYPAPER_CONFIG"; then
        log "attempting waypaper --restore"
        waypaper --restore >/dev/null 2>&1 || true
    else
        log "no waypaper state recorded - attempting waypaper --random"
        waypaper --random >/dev/null 2>&1 || true
    fi

    sleep 0.5

    if wallpaper_is_active; then
        p="$(active_path)"
        remember "$p"
        sync_conf "$p"
        log "waypaper succeeded: $p"
        exit 0
    fi

    log "waypaper reported success but set nothing - falling through"
fi

# Attempt 2: the last wallpaper we successfully applied, in HyprX's own state - it
# survives an `hyprx install`, which clobbers waypaper's config.ini.

if p="$(remembered)"; then
    log "retrying last known wallpaper: $p"
    if apply_direct "$p"; then
        remember "$p"
        sync_conf "$p"
        log "restored $p"
        exit 0
    fi
fi

# Attempt 3: write hyprpaper.conf directly and restart hyprpaper, using any
# image from the folder.

if ! img="$(first_image)"; then
    log "FAILED - no usable image found in $WALLPAPER_DIR"
    exit 1
fi

log "falling back to folder image: $img"

if apply_direct "$img"; then
    remember "$img"
    log "fallback succeeded: $img"
    exit 0
fi

log "FAILED - found $img but hyprpaper would not load it (see hyprpaper output above)"
exit 1
