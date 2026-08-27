#!/usr/bin/env bash

# Kill watchers BEFORE wiping - if a watcher is still alive while
# cliphist wipe runs, an in-flight write can land right after the
# wipe and leave one item behind.
pkill -f "wl-paste --type text --watch cliphist store"
pkill -f "wl-paste --type image --watch cliphist store"
sleep 0.2

cliphist wipe

# wl-paste --watch captures whatever is CURRENTLY in the clipboard
# the instant it starts, not just future changes. Without clearing
# the live clipboard too, restarting the watcher immediately re-adds
# the last item right back.
wl-copy --clear

wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

notify-send "HyprX" "Clipboard history cleared"

# Force the waybar widget to refresh immediately instead of waiting
# up to 5 seconds for its next poll - otherwise the counter still
# shows the old number for a moment after clearing.
pkill -RTMIN+8 waybar
