#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BACKUP_DIR="${HOME}/.config/hyprx-backup"

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backup directory not found."
    exit 1
fi

echo "Restoring configuration..."

cp -r "$BACKUP_DIR"/* "${HOME}/.config/"

echo "Restore complete."