#!/usr/bin/env bash

BACKUP="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP"

cp -r ~/.config/hypr "$BACKUP"
cp -r ~/.config/waybar "$BACKUP" 2>/dev/null || true
cp -r ~/.config/rofi "$BACKUP" 2>/dev/null || true

echo "Backup created at"

echo "$BACKUP"