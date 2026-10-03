#!/usr/bin/env bash

# Restore a backup made by backup-config.sh.
#
#   restore-config.sh                      # newest backup
#   restore-config.sh 20261003-120000      # a specific one
#
# This used to read ~/.config/hyprx-backup, a path nothing ever wrote, while
# backup-config.sh wrote to ~/.config-backup-<ts>. It could therefore never
# restore anything. Both sides now use ~/.config-backup/.

set -euo pipefail

BACKUP_ROOT="${HOME}/.config-backup"

if [[ ! -d "$BACKUP_ROOT" ]]; then
    echo "No backups found at $BACKUP_ROOT"
    echo "Create one with: backup-config.sh"
    exit 1
fi

if [[ -n "${1:-}" ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$1"
else
    # Newest by name, which is a timestamp and therefore sorts correctly.
    BACKUP_DIR="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1)"
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backup not found: $BACKUP_DIR"
    echo
    echo "Available:"
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' 2>/dev/null | sort
    exit 1
fi

if [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    echo "Backup is empty: $BACKUP_DIR"
    exit 1
fi

echo "Restoring from:"
echo "  $BACKUP_DIR"
echo

# Show what is about to be overwritten rather than replacing it silently - this
# replaces live working configuration.
for dir in "$BACKUP_DIR"/*/; do
    name="$(basename "$dir")"
    if [[ -d "$HOME/.config/$name" ]]; then
        echo "  overwrite  ~/.config/$name"
    else
        echo "  create    ~/.config/$name"
    fi
done
echo

read -rp "Proceed? [y/N]: " answer
case "$answer" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) echo "Cancelled."; exit 0 ;;
esac

# Replace atomically where possible: a config watcher must not catch a
# half-copied directory. This is the same two-rename approach deploy.sh uses.
for dir in "$BACKUP_DIR"/*/; do
    name="$(basename "$dir")"
    target="$HOME/.config/$name"

    if [[ -d "$target" ]]; then
        mv "$target" "${target}.restore-old.$$"
        cp -r "$dir" "$target"
        rm -rf "${target}.restore-old.$$"
    else
        cp -r "$dir" "$target"
    fi

    echo "  restored  $name"
done

echo
echo "Restore complete."
echo "Reload with: hyprctl reload   (and restart waybar for bar changes)"
