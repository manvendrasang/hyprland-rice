#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Testing install.sh/uninstall.sh..."

INSTALL_TEST_ROOT="$(mktemp -d)"

export HYPRX_INSTALL_DIR="$INSTALL_TEST_ROOT/share/hyprx"
export HYPRX_BIN_DIR="$INSTALL_TEST_ROOT/bin"

bash "$ROOT_DIR/install.sh" >/dev/null

[[ -d "$HYPRX_INSTALL_DIR" ]]
[[ -f "$HYPRX_INSTALL_DIR/bin/hyprx" ]]
[[ -L "$HYPRX_BIN_DIR/hyprx" ]]
[[ ! -d "$HYPRX_INSTALL_DIR/.git" ]]

# The installed copy should actually run standalone
"$HYPRX_BIN_DIR/hyprx" help >/dev/null

# Re-running install should be safe (idempotent)
bash "$ROOT_DIR/install.sh" >/dev/null
[[ -f "$HYPRX_INSTALL_DIR/bin/hyprx" ]]

bash "$ROOT_DIR/uninstall.sh" >/dev/null

[[ ! -d "$HYPRX_INSTALL_DIR" ]]
[[ ! -e "$HYPRX_BIN_DIR/hyprx" ]]

rm -rf "$INSTALL_TEST_ROOT"

echo "Install/uninstall OK."
