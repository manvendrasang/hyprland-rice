#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing config deployment..."

TARGET="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr"

# Ensure clean slate: target should not exist yet
rm -rf "$TARGET"

CONFIG_BACKUPS=()

# First deploy: nothing existed before
deploy_config_dir hypr

assert_true test -d "$TARGET"
assert_true test -f "$TARGET/hyprland.lua"
assert_equals "hypr:false" "${CONFIG_BACKUPS[0]}"

# Simulate a user having customized their deployed config
echo "# user edit" >> "$TARGET/hyprland.lua"

CONFIG_BACKUPS=()

# Redeploy: this time something existed and should be backed up
deploy_config_dir hypr

assert_equals "hypr:true" "${CONFIG_BACKUPS[0]}"

BACKUP_DIR="$(config_backup_dir_for "$(current_snapshot_id)")/hypr"

assert_true test -d "$BACKUP_DIR"
assert_true grep -q "user edit" "$BACKUP_DIR/hyprland.lua"

# The live target should now match the source again, no user edit
assert_false grep -q "user edit" "$TARGET/hyprland.lua"

echo "Config deployment OK."
