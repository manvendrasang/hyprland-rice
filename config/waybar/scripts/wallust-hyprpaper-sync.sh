#!/usr/bin/env bash
# Polls hyprpaper directly for its active wallpaper, independent of
# whatever set it - waypaper's picker, a keybind, a manual hyprctl
# call, anything. hyprpaper is the actual source of truth for "what
# wallpaper is showing right now"; waypaper's own post_command only
# fires when waypaper itself changes it, which misses every other
# path. This is a strict superset, so it replaces that hook entirely
# rather than running alongside it (see waypaper/config.ini).
#
# Also applies once at session start against whatever wallpaper is
# already active when this daemon starts - not just on later changes
# - so colors are correct from the first session, not only after the
# next manual wallpaper change.

set -uo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v wallust >/dev/null 2>&1 || exit 0

# Give hyprpaper a moment to come up and restore its wallpaper before
# the first poll, so this doesn't race hyprpaper's own startup
# sequence (same class of issue as the sleep 1 guards elsewhere in
# hyprland.lua's autostart block).
sleep 2

last_state=""

while true; do
    current_state=$(hyprctl hyprpaper listactive 2>/dev/null || true)

    if [[ -n "$current_state" && "$current_state" != "$last_state" ]]; then
        last_state="$current_state"
        # listactive prints one line per monitor. Current hyprpaper
        # (0.8.x, per the wiki) prints "MONITOR: /path"; older builds
        # printed "MONITOR = /path", and an unassigned fallback shows
        # up with an empty monitor name. Handle both separators, skip
        # any line whose path doesn't exist on disk (ghost/fallback
        # entries), and use the first real one - one wallpaper is
        # representative enough for a single palette.
        wallpaper_path=""
        while IFS= read -r line; do
            candidate=$(printf '%s' "$line" | sed -E 's/^[^=:]*(=|:) *//')
            if [[ -n "$candidate" && -f "$candidate" ]]; then
                wallpaper_path="$candidate"
                break
            fi
        done <<< "$current_state"
        if [[ -n "$wallpaper_path" && -f "$wallpaper_path" ]]; then
            ~/.local/share/hyprx/scripts/apply-wallust-theme.sh "$wallpaper_path"
        fi
    fi

    sleep 2
done
