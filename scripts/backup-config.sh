#!/usr/bin/env bash

set -euo pipefail

BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

cp -r "$HOME/.config/hypr" "$BACKUP_DIR"

[[ -d "$HOME/.config/waybar" ]] && cp -r "$HOME/.config/waybar" "$BACKUP_DIR"
[[ -d "$HOME/.config/rofi" ]] && cp -r "$HOME/.config/rofi" "$BACKUP_DIR"

echo "Backup created at"
echo "$BACKUP_DIR"