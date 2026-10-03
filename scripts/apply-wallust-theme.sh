#!/usr/bin/env bash
# Triggered by scripts/wallust-hyprpaper-sync.sh on every wallpaper change: regenerates
# the templated colors via wallust, then reloads only the long-running daemons.

set -uo pipefail

WALLPAPER="${1:-}"

if [[ -z "$WALLPAPER" ]]; then
    exit 0
fi

command -v wallust >/dev/null 2>&1 || exit 0

wallust run "$WALLPAPER" --quiet --check-contrast

# Keep hyprpaper.conf pointing at the wallpaper that is actually live.
# Runs on every wallpaper change, not just at login: waypaper never updates
# hyprpaper.conf, so without this the conf drifts to a stale path and the next
# hyprpaper restart reverts the wallpaper or comes up with nothing at all.
HYPRX_SYNC_CONF="${HYPRX_TARGET_HOME:-$HOME}/.local/share/hyprx/scripts/sync-hyprpaper-conf.sh"
# if/then rather than `[[ -x … ]] && "$…" || true`. The &&/|| form is not
# if-then-else: the trailing `|| true` is a third statement that runs whenever
# the sync script itself fails, so a sync failure and a missing script are
# indistinguishable - and neither was reported. Here both are handled, and the
# sync failure is visible in the log instead of vanishing.
if [[ -x "$HYPRX_SYNC_CONF" ]]; then
    if ! "$HYPRX_SYNC_CONF" "$WALLPAPER"; then
        echo "apply-wallust-theme: could not sync hyprpaper.conf" >&2
    fi
else
    echo "apply-wallust-theme: $HYPRX_SYNC_CONF is missing or not executable" >&2
fi

# Waybar only reads colors.css at (re)start.
~/.local/share/hyprx/scripts/reload-waybar.sh >/dev/null 2>&1 &

# swaync supports a live CSS reload without losing notification history.
if command -v swaync-client >/dev/null 2>&1; then
    swaync-client --reload-css >/dev/null 2>&1 &
fi

# Hyprland's border colors are read via require("colors") at config
# parse time, so they need a full reload to pick up the new file.
if command -v hyprctl >/dev/null 2>&1; then
    ~/.local/share/hyprx/scripts/reload-hypr.sh >/dev/null 2>&1 &
fi

wait
