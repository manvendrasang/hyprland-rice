#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Syncing Waybar..."

rm -rf "$HOME/.config/waybar"

cp -r "$ROOT_DIR/config/waybar" "$HOME/.config/"

pkill -x waybar 2>/dev/null || true

nohup waybar >/dev/null 2>&1 &