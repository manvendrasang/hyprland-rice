#!/usr/bin/env bash

# Waybar's exec environment has failed to resolve GUI apps called as a bare
# command string even when they run fine from a shell, so look them up
# explicitly and notify rather than silently no-op.

if command -v pavucontrol >/dev/null 2>&1; then
    exec pavucontrol
else
    notify-send "HyprX" "pavucontrol not found. Try: pacman -Q pavucontrol"
fi
