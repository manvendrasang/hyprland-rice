#!/usr/bin/env bash

# See sound-manager.sh for why this indirection exists.

if command -v nm-connection-editor >/dev/null 2>&1; then
    exec nm-connection-editor
else
    notify-send "HyprX" "nm-connection-editor not found. Try: pacman -Q nm-connection-editor"
fi
