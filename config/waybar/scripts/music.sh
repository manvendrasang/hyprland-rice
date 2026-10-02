#!/usr/bin/env bash
# Signal-driven: music-daemon.sh is the only thing that calls playerctl, and
# this just prints whatever the daemon last wrote.

CACHE_FILE="$HOME/.cache/hyprx/waybar-music.json"

if [[ -s "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
else
    printf '{"text":"","tooltip":"","class":"stopped"}\n'
fi
