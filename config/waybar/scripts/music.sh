#!/usr/bin/env bash
# Waybar's custom/music module is now signal-driven - see
# music-daemon.sh, which is the only thing that ever calls playerctl.
# This script just prints whatever the daemon last wrote out.

CACHE_FILE="$HOME/.cache/hyprx/waybar-music.json"

if [[ -s "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
else
    printf '{"text":"","tooltip":"","class":"stopped"}\n'
fi
