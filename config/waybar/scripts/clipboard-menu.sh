#!/usr/bin/env bash

selection=$(
    cliphist list |
    rofi -dmenu \
        -i \
        -p "Clipboard" \
        -theme ~/.config/rofi/dmenu.rasi
)

[[ -z "$selection" ]] && exit

printf "%s" "$selection" | cliphist decode | wl-copy
