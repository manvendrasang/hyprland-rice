#!/usr/bin/env bash

# Launches the system monitor from a waybar click. See lib-launch.sh.
#
# Mission Center's package name and its binary name have differed across
# packaging methods, so both spellings are tried - and a miss is reported,
# since a silent exec failure from waybar looks identical to "nothing happened".

LIB="$(dirname "$0")/lib-launch.sh"
if [[ -f "$LIB" ]]; then
    # shellcheck disable=SC1090
    source "$LIB"
    hyprx_launch_or_notify mission-center missioncenter
else
    notify-send "HyprX" "launcher helper missing - re-run: hyprx install"
    exit 1
fi
