#!/usr/bin/env bash

# Launches nm-connection-editor from a waybar click. See lib-launch.sh.

LIB="$(dirname "$0")/lib-launch.sh"
if [[ -f "$LIB" ]]; then
    # shellcheck disable=SC1090
    source "$LIB"
    hyprx_launch_or_notify nm-connection-editor
else
    notify-send "HyprX" "launcher helper missing - re-run: hyprx install"
    exit 1
fi
