#!/usr/bin/env bash

# Installs the HyprX tool itself to a stable location, separate from wherever
# the repo is cloned - so `hyprx` does not depend on which branch is checked
# out here. This is NOT `hyprx install`, which installs packages and configs
# onto the system.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTALL_DIR="${HYPRX_INSTALL_DIR:-$HOME/.local/share/hyprx}"
BIN_DIR="${HYPRX_BIN_DIR:-$HOME/.local/bin}"

echo "Installing HyprX to $INSTALL_DIR..."

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

cp -r "$ROOT_DIR"/. "$INSTALL_DIR"/

rm -rf "$INSTALL_DIR/.git"

mkdir -p "$BIN_DIR"

ln -sf "$INSTALL_DIR/bin/hyprx" "$BIN_DIR/hyprx"
ln -sf "$INSTALL_DIR/scripts/prime-run.sh" "$BIN_DIR/prime-run"
ln -sf "$INSTALL_DIR/scripts/settings-menu.sh" "$BIN_DIR/hyprx-settings"

echo "Installed: $BIN_DIR/hyprx -> $INSTALL_DIR/bin/hyprx"
echo "Installed: $BIN_DIR/prime-run -> $INSTALL_DIR/scripts/prime-run.sh"
echo "Installed: $BIN_DIR/hyprx-settings -> $INSTALL_DIR/scripts/settings-menu.sh"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo
        echo "Note: $BIN_DIR is not on your PATH."
        echo "Add this to your shell rc file, then open a new shell:"
        echo "    export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

echo
echo "Run 'hyprx help' to get started."
