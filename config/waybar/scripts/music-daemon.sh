#!/usr/bin/env bash
# One long-lived process blocking on playerctl's own --follow stream, so
# Waybar is only written to and signalled on a real state change. music.sh
# (what Waybar execs) just cats whatever this daemon last wrote.

set -uo pipefail

CACHE_DIR="$HOME/.cache/hyprx"
CACHE_FILE="$CACHE_DIR/waybar-music.json"
mkdir -p "$CACHE_DIR"

command -v playerctl >/dev/null 2>&1 || exit 0

# Player preference order, highest first.
PRIORITY=(spotify spotifyd brave firefox mpv vlc)

declare -A STATUS TITLE ARTIST ALBUM

hide() {
    printf '{"text":"","tooltip":"","class":"stopped"}\n' > "$CACHE_FILE"
    pkill -RTMIN+9 waybar 2>/dev/null
}

write_state() {
    local best="" name p

    # Prefer a priority player that's actively playing...
    for name in "${PRIORITY[@]}"; do
        for p in "${!STATUS[@]}"; do
            if [[ "$p" == "$name"* && "${STATUS[$p]}" == "Playing" ]]; then
                best="$p"; break 2
            fi
        done
    done

    # ...else fall back to the highest-priority player in any state.
    if [[ -z "$best" ]]; then
        for name in "${PRIORITY[@]}"; do
            for p in "${!STATUS[@]}"; do
                [[ "$p" == "$name"* ]] && { best="$p"; break 2; }
            done
        done
    fi

    if [[ -z "$best" || "${STATUS[$best]:-Stopped}" == "Stopped" || -z "${TITLE[$best]:-}" ]]; then
        hide
        return
    fi

    local text="${TITLE[$best]} • ${ARTIST[$best]}"
    local max=48
    (( ${#text} > max )) && text="${text:0:max-3}..."
    local class="${STATUS[$best],,}"

    printf '{"text":"󰎆 %s","tooltip":"%s\\n%s\\n%s","class":"%s"}\n' \
        "$text" "${TITLE[$best]}" "${ARTIST[$best]}" "${ALBUM[$best]}" "$class" \
        > "$CACHE_FILE"

    pkill -RTMIN+9 waybar 2>/dev/null
}

hide

playerctl --all-players --follow metadata \
    --format '{{playerName}}|{{status}}|{{title}}|{{artist}}|{{album}}' 2>/dev/null |
while IFS='|' read -r name status title artist album; do
    [[ -z "$name" ]] && continue
    STATUS[$name]="$status"
    TITLE[$name]="$title"
    ARTIST[$name]="$artist"
    ALBUM[$name]="$album"
    write_state
done
