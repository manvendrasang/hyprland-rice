#!/usr/bin/env bash

CLEAR_OPTION="🗑️  Clear clipboard history"

selection=$(
    { echo "$CLEAR_OPTION"; cliphist list; } |
    rofi -dmenu \
        -i \
        -p "Clipboard"
)

[[ -z "$selection" ]] && exit

if [[ "$selection" == "$CLEAR_OPTION" ]]; then
    cliphist wipe
    notify-send "HyprX" "Clipboard history cleared"
    exit
fi

printf "%s" "$selection" | cliphist decode | wl-copy