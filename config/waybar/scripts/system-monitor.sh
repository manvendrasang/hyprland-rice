#!/usr/bin/env bash

# Mission Center's Arch package name (mission-center) and its actual
# binary name have differed across packaging methods historically.
# Try both rather than assume, and surface a real error if neither exists -
# a silent exec failure from Waybar looks identical to "nothing happened".

if command -v mission-center >/dev/null 2>&1; then
    exec mission-center
elif command -v missioncenter >/dev/null 2>&1; then
    exec missioncenter
else
    notify-send "HyprX" "System monitor not found. Try: pacman -Q mission-center"
fi
