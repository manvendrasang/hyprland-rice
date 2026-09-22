#!/usr/bin/env bash
# Triggered by waypaper's post_command (see config/waypaper/config.ini)
# every time the wallpaper changes. Regenerates every templated color
# file via wallust (config/wallust/wallust.toml), then reloads only
# what doesn't already pick up a changed file on its own.
#
# Rofi and wlogout are launched fresh every time they're opened, so
# they need no reload here - the next launch just reads the new
# colors.rasi / colors.css. Waybar and swaync are long-running
# daemons, so they do need to be told.

set -uo pipefail

WALLPAPER="${1:-}"

if [[ -z "$WALLPAPER" ]]; then
    exit 0
fi

command -v wallust >/dev/null 2>&1 || exit 0

wallust run "$WALLPAPER" --quiet

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
