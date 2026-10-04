#!/usr/bin/env bash

# The one parser for `hyprctl hyprpaper listactive`.
#
# This existed twice, and the two copies disagreed about the format. One
# stripped "MONITOR:" and the other handled "MONITOR: /path", "MONITOR = /path"
# and a nameless fallback. The stricter one silently returned nothing on a
# build that prints the other form, which looks exactly like "no wallpaper is
# set" - so the colour regeneration never fired and the rice kept the colours
# of a wallpaper that was no longer there.
#
# Returns the first path that actually exists on disk, so a stale entry in
# hyprpaper's own state cannot be handed to wallust as a wallpaper.

hyprx_wallpaper_active() {
    local line candidate

    while IFS= read -r line; do
        # "MONITOR: /path", "MONITOR = /path", or a bare path with no name.
        candidate="$(printf '%s' "$line" | sed -E 's/^[^=:]*(=|:) *//')"
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(hyprctl hyprpaper listactive 2>/dev/null)

    return 1
}

# True when hyprpaper currently has a wallpaper loaded.
hyprx_wallpaper_is_set() {
    local active
    active="$(hyprctl hyprpaper listactive 2>/dev/null || true)"
    [[ -n "${active//[[:space:]]/}" ]]
}
# Regenerate every colour from a wallpaper, through the cache.
#
# Split out from apply-wallust-theme.sh so `hyprx wallpaper set` can do the same
# thing without going through the polling daemon. The daemon polls every 2s,
# which is right for a change you did not make yourself and wrong for one you
# just asked for.
hyprx_wallpaper_apply_colours() {
    local wallpaper="$1"

    [[ -z "$wallpaper" ]] && return 0
    [[ -f "$wallpaper" ]] || return 0

    local script="${HYPRX_TARGET_HOME:-$HOME}/.local/share/hyprx/scripts/apply-wallust-theme.sh"

    if [[ ! -x "$script" ]]; then
        hyprx_ui_error "apply-wallust-theme.sh is missing or not executable: $script"
        return 1
    fi

    "$script" "$wallpaper"
}
