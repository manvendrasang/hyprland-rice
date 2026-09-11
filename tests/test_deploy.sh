#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing config deployment..."

init_snapshot_id

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

#############################################
# Orphaned-target cleanup
#############################################

echo "Testing orphaned-target cleanup..."

ORPHAN_TARGET="${HYPRX_TARGET_HOME:-$HOME}/.config/orphan-theme"

# Simulate a directory deployed by a previous
# run that is no longer in HYPRX_CONFIG_TARGETS
# (e.g. a reverted feature like BUG-12's gtk-3.0
# glassmorphism override).
rm -rf "$ORPHAN_TARGET"
mkdir -p "$ORPHAN_TARGET"
echo "leftover glass override" > "$ORPHAN_TARGET/gtk.css"

write_deployed_targets hypr orphan-theme

CONFIG_BACKUPS=()

HYPRX_CONFIG_TARGETS="hypr" remove_orphaned_targets

assert_false test -e "$ORPHAN_TARGET"
assert_equals "orphan-theme:true" "${CONFIG_BACKUPS[0]}"

ORPHAN_BACKUP="$(config_backup_dir_for "$(current_snapshot_id)")/orphan-theme"

assert_true test -f "$ORPHAN_BACKUP/gtk.css"
assert_true grep -q "leftover glass override" "$ORPHAN_BACKUP/gtk.css"

# A target still in the current list must never be touched.
assert_true test -d "$TARGET"

# A target that never existed on disk must not error or
# fabricate a backup entry.
CONFIG_BACKUPS=()
write_deployed_targets hypr never-deployed
HYPRX_CONFIG_TARGETS="hypr" remove_orphaned_targets
assert_equals "0" "${#CONFIG_BACKUPS[@]}"

echo "Orphaned-target cleanup OK."
