#!/usr/bin/env bash

# Uninstalls the HyprX tool itself. This does NOT undo anything HyprX installed
# on your system (packages, deployed configs) - use `hyprx rollback` first if
# you need that.

set -euo pipefail

INSTALL_DIR="${HYPRX_INSTALL_DIR:-$HOME/.local/share/hyprx}"
BIN_DIR="${HYPRX_BIN_DIR:-$HOME/.local/bin}"

echo "Removing HyprX..."

rm -rf "$INSTALL_DIR"

# All three must go, or a dangling symlink is left pointing into the removed
# INSTALL_DIR.
rm -f "$BIN_DIR/hyprx"
rm -f "$BIN_DIR/prime-run"
rm -f "$BIN_DIR/hyprx-settings"

echo "Removed $INSTALL_DIR, $BIN_DIR/hyprx, $BIN_DIR/prime-run, $BIN_DIR/hyprx-settings"
echo
echo "Note: this only removes the HyprX tool itself."
echo "It does not undo any packages or configs HyprX previously"
echo "installed on your system. Run 'hyprx rollback' for that"
echo "before uninstalling, if you still need to."
