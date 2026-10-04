#!/usr/bin/env bash
# Polls hyprpaper itself - the source of truth for every wallpaper change, not
# just waypaper's own - so this replaces waypaper's post_command hook entirely.

set -uo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v wallust >/dev/null 2>&1 || exit 0

# Let hyprpaper restore its wallpaper before the first poll, so this does not
# race its startup (same class of guard as the sleeps in hyprland.lua).
sleep 2

last_state=""

while true; do
    current_state=$(hyprctl hyprpaper listactive 2>/dev/null || true)

    if [[ -n "$current_state" && "$current_state" != "$last_state" ]]; then
        last_state="$current_state"
        # The one parser for this output, shared with wallpaper-restore.sh.
        # Two copies disagreed about the format and the stricter one silently
        # returned nothing on builds that print the other form.
        wallpaper_path="$(hyprx_wallpaper_active || true)"
        if [[ -n "$wallpaper_path" && -f "$wallpaper_path" ]]; then
            ~/.local/share/hyprx/scripts/apply-wallust-theme.sh "$wallpaper_path"
        fi
    fi

    sleep 2
done
