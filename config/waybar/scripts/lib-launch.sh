#!/usr/bin/env bash
# Shared helper for the waybar click-launchers (sound-manager.sh,
# wifi-manager.sh, system-monitor.sh).
#
# Waybar's exec environment has failed to resolve GUI apps called as a bare
# command string even when they run fine from a shell, so every launcher looks
# its binary up explicitly and notifies rather than silently no-op'ing: a
# silent exec failure from a bar click looks identical to "nothing happened".
#
# This is sourced, not executed, and it lives next to its callers so the path
# is always `$(dirname "$0")/lib-launch.sh` - no dependency on the installed
# tree, which a click-launcher cannot assume (a broken install must still
# report itself, not silently die).
#
# Tries each name in order and execs the first one found, so callers with
# alternate spellings (mission-center vs missioncenter) stay one line.

# shellcheck disable=SC2317,SC2329  # reached via the launchers, not executed directly
hyprx_launch_or_notify() {
    (( $# > 0 )) || return 1

    local bin
    for bin in "$@"; do
        if command -v "$bin" >/dev/null 2>&1; then
            exec "$bin"
        fi
    done

    notify-send "HyprX" "$1 not found. Try: pacman -Q $1"
}
