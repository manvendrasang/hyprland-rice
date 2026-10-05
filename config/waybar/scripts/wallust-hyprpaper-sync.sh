#!/usr/bin/env bash
# Polls hyprpaper itself - the source of truth for every wallpaper change, not
# just waypaper's own - so this replaces waypaper's post_command hook entirely.

set -uo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v wallust >/dev/null 2>&1 || exit 0

# Let hyprpaper restore its wallpaper before the first poll, so this does not
# race its startup (same class of guard as the sleeps in autostart.lua).
sleep 2

last_state=""

# The active-wallpaper parser lives in lib/wallpaper.sh, but this daemon runs
# standalone - it is launched from autostart.lua, not through the hyprx CLI, so
# nothing has sourced the library. Source it from the installed location when
# present; otherwise fall back to the same parsing inline so the daemon keeps
# working instead of silently resolving every wallpaper to nothing (an unknown
# command inside $(...) with `|| true` yields an empty path, and an empty path
# looks exactly like "no wallpaper is set").
for _wallpaper_lib in \
    "${HYPRX_TARGET_HOME:-$HOME}/.local/share/hyprx/lib/wallpaper.sh" \
    "$(dirname "$(dirname "$(dirname "$0")")")/lib/wallpaper.sh"; do
    # shellcheck disable=SC1090
    [[ -f "$_wallpaper_lib" ]] && source "$_wallpaper_lib" && break
done
unset _wallpaper_lib

if ! command -v hyprx_wallpaper_active >/dev/null 2>&1; then
    hyprx_wallpaper_active() {
        local line candidate
        while IFS= read -r line; do
            candidate="$(printf '%s' "$line" | sed -E 's/^[^=:]*(=|:) *//')"
            if [[ -n "$candidate" && -f "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done < <(hyprctl hyprpaper listactive 2>/dev/null)
        return 1
    }
fi

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
