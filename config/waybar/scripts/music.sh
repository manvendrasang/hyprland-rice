#!/usr/bin/env bash

PLAYER=$(playerctl -l | grep -E 'spotify|spotifyd|brave|firefox|mpv|vlc' | head -n1)

[[ -z "$PLAYER" ]] && exit 0

STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null)

[[ "$STATUS" == "Stopped" ]] && exit 0

META=$(playerctl -p "$PLAYER" metadata \
    --format '{{title}}|{{artist}}|{{album}}' 2>/dev/null)

IFS='|' read -r TITLE ARTIST ALBUM <<< "$META"

[[ -z "$TITLE" ]] && exit 0

TEXT="$TITLE • $ARTIST"

MAX=48

if (( ${#TEXT} > MAX )); then
    TEXT="${TEXT:0:MAX-3}..."
fi

CLASS=$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')

printf '{"text":"󰎆 %s","tooltip":"%s\\n%s\\n%s","class":"%s"}\n' \
"$TEXT" \
"$TITLE" \
"$ARTIST" \
"$ALBUM" \
"$CLASS"