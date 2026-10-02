#!/usr/bin/env bash

# Mission Center's package name and its binary name have differed across
# packaging methods, so try both - and report, since a silent exec failure
# from Waybar looks identical to "nothing happened".

if command -v mission-center >/dev/null 2>&1; then
    exec mission-center
elif command -v missioncenter >/dev/null 2>&1; then
    exec missioncenter
else
    notify-send "HyprX" "System monitor not found. Try: pacman -Q mission-center"
fi
