#!/usr/bin/env bash

########################################
# Uninstall HyprX itself
########################################
#
# Removes the installed copy of the tool.
# This does NOT undo anything HyprX
# installed on your system (packages,
# deployed configs) - use `hyprx rollback`
# for that, before running this, if needed.
#

set -euo pipefail

INSTALL_DIR="${HYPRX_INSTALL_DIR:-$HOME/.local/share/hyprx}"
BIN_DIR="${HYPRX_BIN_DIR:-$HOME/.local/bin}"

echo "Removing HyprX..."

rm -rf "$INSTALL_DIR"
rm -f "$BIN_DIR/hyprx"

echo "Removed $INSTALL_DIR and $BIN_DIR/hyprx"
echo
echo "Note: this only removes the HyprX tool itself."
echo "It does not undo any packages or configs HyprX previously"
echo "installed on your system. Run 'hyprx rollback' for that"
echo "before uninstalling, if you still need to."
