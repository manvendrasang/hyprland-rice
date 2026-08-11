#!/usr/bin/env bash

# Waybar's exec environment has, in practice, failed to resolve some
# GUI apps called as a bare command string even when they run fine from
# an interactive shell. Route through an explicit PATH lookup and give
# visible feedback if it's genuinely missing, rather than a silent no-op.

if command -v pavucontrol >/dev/null 2>&1; then
    exec pavucontrol
else
    notify-send "HyprX" "pavucontrol not found. Try: pacman -Q pavucontrol"
fi
