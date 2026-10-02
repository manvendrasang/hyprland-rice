#!/usr/bin/env bash

# Kill watchers BEFORE wiping: a still-live watcher can write an in-flight
# item just after the wipe and leave one item behind.
pkill -f "wl-paste --type text --watch cliphist store"
pkill -f "wl-paste --type image --watch cliphist store"
sleep 0.2

cliphist wipe

# wl-paste --watch stores whatever is CURRENTLY in the clipboard the instant
# it starts, so clear the live clipboard too or it re-adds the last item.
wl-copy --clear

wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

notify-send "HyprX" "Clipboard history cleared"

# Signal waybar so the counter updates now instead of on its next poll (up to
# 5s later, still showing the pre-wipe count).
pkill -RTMIN+8 waybar
