#!/usr/bin/env bash

########################################
# Install HyprX itself
########################################
#
# This installs the HyprX tool to a stable
# location, separate from wherever you
# cloned the repo. Once installed, `hyprx`
# no longer depends on which git branch
# happens to be checked out here - it's a
# real, standalone copy.
#
# This is NOT "hyprx install" (which
# installs packages/configs onto your
# system). This installs the tool itself.
#

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

echo "Installed: $BIN_DIR/hyprx -> $INSTALL_DIR/bin/hyprx"

case ":$PATH:" in
    *":$BIN_DIR:"*)
        ;;
    *)
        echo
        echo "Note: $BIN_DIR is not on your PATH."
        echo "Add this to your shell rc file, then open a new shell:"
        echo "    export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

echo
echo "Run 'hyprx help' to get started."
