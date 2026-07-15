#!/usr/bin/env bash

selection=$(
    cliphist list |
    rofi -dmenu \
        -i \
        -p "Clipboard"
)

[[ -z "$selection" ]] && exit

printf "%s" "$selection" | cliphist decode | wl-copy