#!/usr/bin/env bash
# Reload waybar (after a theme change)
#
# waybar only reads colors.css at (re)start, so a wallpaper change has to restart
# it. The old blind `pkill` + unverified restart left the bar gone for a whole session.

set -uo pipefail

ENSURE_WAYBAR="${HYPRX_ENSURE_WAYBAR:-${HYPRX_TARGET_HOME:-$HOME}/.config/waybar/scripts/ensure-waybar.sh}"

if [[ ! -x "$ENSURE_WAYBAR" ]]; then
    # Deliberately no "start waybar directly" fallback: it would be the exact
    # unverified start this script exists to eliminate, so report a broken install.
    printf '[reload-waybar] FATAL: %s is missing or not executable.\n' "$ENSURE_WAYBAR" >&2
    printf '[reload-waybar] The install is incomplete - re-run: hyprx install\n' >&2
    exit 1
fi

exec "$ENSURE_WAYBAR" --restart
