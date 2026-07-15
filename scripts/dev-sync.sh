#!/usr/bin/env bash

set -e

ROOT="$HOME/Projects/hyprland-rice"

echo "Syncing..."

mkdir -p ~/.config

rsync -av --delete \
"$ROOT/config/hypr/" \
~/.config/hypr/

rsync -av --delete \
"$ROOT/config/waybar/" \
~/.config/waybar/

hyprctl reload

pkill waybar || true

waybar >/dev/null 2>&1 &