#!/usr/bin/env bash
# waybar's layer-shell surface can lose an early-session race against
# Hyprland/the Wayland socket not being fully ready yet, with no
# error logged anywhere - it just silently never launches. A fixed
# `sleep 1 && waybar` helped but wasn't reliable on every boot (a
# heavier/slower one - e.g. right after installing a lot of new
# packages - can still exceed a 1s margin). This retries until waybar
# is confirmed actually running, instead of guessing a fixed delay.

set -uo pipefail

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x waybar >/dev/null 2>&1; then
        exit 0
    fi
    waybar &
    sleep 1
done
