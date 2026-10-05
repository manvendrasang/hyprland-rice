#!/usr/bin/env bash

# Launches pavucontrol from a waybar click. See lib-launch.sh for why the
# indirection exists: a bare command string can fail to resolve in waybar's
# exec environment while working fine from a shell.

LIB="$(dirname "$0")/lib-launch.sh"
if [[ -f "$LIB" ]]; then
    # shellcheck disable=SC1090
    source "$LIB"
    hyprx_launch_or_notify pavucontrol
else
    notify-send "HyprX" "launcher helper missing - re-run: hyprx install"
    exit 1
fi
