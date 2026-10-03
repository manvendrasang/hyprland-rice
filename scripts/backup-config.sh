#!/usr/bin/env bash

# Ad hoc backup of the deployed configs, outside the install pipeline.
#
# For a backup taken as part of an install, use `hyprx rollback` - that one is
# keyed to a snapshot and `hyprx rollback <id>` can actually undo it.
#
# This script used to write to ~/.config-backup-<ts> while restore-config.sh
# read ~/.config/hyprx-backup. Two different paths, so restore could never find
# anything backup had written. Both now use ~/.config-backup/<timestamp>/.

set -euo pipefail

BACKUP_ROOT="${HOME}/.config-backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

# Only what has been deployed. Anything else under ~/.config belongs to other
# tools and is none of this script's business.
for dir in hypr waybar wlogout swaync swappy rofi waypaper wallust gtk-3.0; do
    [[ -d "$HOME/.config/$dir" ]] || continue
    cp -r "$HOME/.config/$dir" "$BACKUP_DIR"
done

if [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    rmdir "$BACKUP_DIR"
    echo "Nothing to back up - no deployed configs found in $HOME/.config"
    echo "Run 'hyprx install' first."
    exit 1
fi

echo "Backup created at"
echo "$BACKUP_DIR"
echo
echo "Restore it with: restore-config.sh $BACKUP_DIR"
