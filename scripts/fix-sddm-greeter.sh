#!/usr/bin/env bash

# Fix SDDM greeter's own Hyprland config
#
# SDDM's greeter runs a separate Hyprland session, so with no config there
# Hyprland auto-generates one - the login screen's banner, flash and cheatsheet.

set -euo pipefail

GREETER_CONFIG_DIR="/var/lib/sddm/.config/hypr"
GREETER_CONFIG_FILE="$GREETER_CONFIG_DIR/hyprland.lua"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "This needs to run as root (writes to $GREETER_CONFIG_DIR, owned by the sddm user)." >&2
    echo "Run: sudo bash scripts/fix-sddm-greeter.sh" >&2
    exit 1
fi

if [[ -f "$GREETER_CONFIG_FILE" ]]; then
    backup="$GREETER_CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
    cp "$GREETER_CONFIG_FILE" "$backup"
    echo "Backed up existing config to $backup"
    # No "skip if exists" guard: this file is only ever either missing, or the
    # one Hyprland itself auto-generates - nothing here is hand-customized.
fi

mkdir -p "$GREETER_CONFIG_DIR"

cat > "$GREETER_CONFIG_FILE" << 'EOF'
-- Minimal config for SDDM's own greeter Hyprland session.
-- This is NOT your session's config (that's ~/.config/hypr/hyprland.lua) -
-- this only exists to stop the greeter from auto-generating a default
-- config (which shows a warning banner, keybind cheatsheet, and the
-- default Hyprland wallpaper on the login screen).

hl.config({
	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
	},
})
EOF

chown -R sddm:sddm "$GREETER_CONFIG_DIR" 2>/dev/null || \
    echo "Note: could not chown to sddm:sddm (continuing - file is still readable)."

echo "Wrote $GREETER_CONFIG_FILE"
echo "Reboot (or restart sddm.service) to see the login screen without the flash/banner."
