#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CLI="$ROOT_DIR/bin/hyprx"

echo "Testing CLI..."

"$CLI" >/dev/null

"$CLI" doctor >/dev/null

"$CLI" clean >/dev/null

"$CLI" profile list >/dev/null

"$CLI" profile current >/dev/null

"$CLI" profile show developer >/dev/null

echo "CLI OK."