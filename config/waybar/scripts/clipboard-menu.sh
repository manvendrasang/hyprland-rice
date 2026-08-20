#!/usr/bin/env bash

CLEAR_OPTION="🗑️  Clear clipboard history"

selection=$(
    { echo "$CLEAR_OPTION"; cliphist list; } |
    rofi -dmenu \
        -i \
        -p "Clipboard" \
        -theme ~/.config/rofi/dmenu.rasi
)

[[ -z "$selection" ]] && exit

if [[ "$selection" == "$CLEAR_OPTION" ]]; then
    (
        cliphist wipe

        # The watchers hold the history db open for the whole session.
        # Wiping it out from under them breaks future recording until
        # they're restarted against the freshly recreated db.
        pkill -f "wl-paste --type text --watch cliphist store"
        pkill -f "wl-paste --type image --watch cliphist store"
        wl-paste --type text --watch cliphist store &
        wl-paste --type image --watch cliphist store &

        notify-send "HyprX" "Clipboard history cleared"
    ) &
    disown
    exit
fi

printf "%s" "$selection" | cliphist decode | wl-copy