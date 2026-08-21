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
        # Kill watchers BEFORE wiping - if a watcher is still alive
        # while cliphist wipe runs, an in-flight write can land right
        # after the wipe and leave one item behind.
        pkill -f "wl-paste --type text --watch cliphist store"
        pkill -f "wl-paste --type image --watch cliphist store"
        sleep 0.2

        cliphist wipe

        # wl-paste --watch captures whatever is CURRENTLY in the
        # clipboard the instant it starts, not just future changes.
        # Without clearing the live clipboard too, restarting the
        # watcher immediately re-adds the last item right back.
        wl-copy --clear

        wl-paste --type text --watch cliphist store &
        wl-paste --type image --watch cliphist store &

        notify-send "HyprX" "Clipboard history cleared"
    ) &
    disown
    exit
fi

printf "%s" "$selection" | cliphist decode | wl-copy