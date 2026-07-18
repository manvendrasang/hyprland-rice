#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Syncing..."

mkdir -p "$HOME/.config"

rsync -a --delete \
    "$ROOT_DIR/config/hypr/" \
    "$HOME/.config/hypr/"

rsync -a --delete \
    "$ROOT_DIR/config/waybar/" \
    "$HOME/.config/waybar/"

hyprctl reload

pkill -x waybar 2>/dev/null || true

nohup waybar >/dev/null 2>&1 &