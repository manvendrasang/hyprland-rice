#!/bin/bash

set -e

echo "Syncing Waybar..."

rm -rf ~/.config/waybar

cp -r ~/Projects/hyprland-rice/config/waybar ~/.config/

pkill waybar

waybar &

# ./scripts/dev-sync.sh