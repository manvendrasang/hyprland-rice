#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Installing Hypr configuration..."

mkdir -p "$HOME/.config"

cp -r "$ROOT_DIR/config/hypr" "$HOME/.config/"

echo "[✓] Installed."