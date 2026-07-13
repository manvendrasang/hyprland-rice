#!/bin/bash

set -e

echo "[*] Installing Hypr configuration..."

mkdir -p ~/.config

cp -r config/hypr ~/.config/

echo "[✓] Installed."
