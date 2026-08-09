#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CLI="$ROOT_DIR/bin/hyprx"

echo "Testing CLI..."

"$CLI" >/dev/null

"$CLI" doctor >/dev/null

"$CLI" clean >/dev/null

"$CLI" rollback list >/dev/null

echo "CLI OK."
