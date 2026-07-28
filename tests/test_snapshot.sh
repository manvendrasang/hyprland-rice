#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing snapshot/rollback..."

# Stub remove_package so this test never touches real packages
remove_package() {
    echo "stub-removed: $1"
    return 0
}

INSTALLED_PACKAGES=(fake-pkg-one fake-pkg-two)
PROFILE="testprofile"

save_snapshot

assert_not_empty "$LAST_SNAPSHOT_ID"

SNAPSHOT_ID="$LAST_SNAPSHOT_ID"

assert_true snapshot_exists "$SNAPSHOT_ID"

# list_snapshots should mention our snapshot id
assert_true grep -q "$SNAPSHOT_ID" <(list_snapshots)

# snapshot_packages should return exactly what we saved
PACKAGES_OUT="$(snapshot_packages "$SNAPSHOT_ID")"
assert_equals "$(printf 'fake-pkg-one\nfake-pkg-two')" "$PACKAGES_OUT"

# latest_snapshot should find it
assert_equals "$SNAPSHOT_ID" "$(latest_snapshot)"

# rollback should succeed and remove the snapshot file afterward
rollback_snapshot "$SNAPSHOT_ID" >/dev/null

assert_false snapshot_exists "$SNAPSHOT_ID"

########################################
# Combined package + config snapshot
########################################

CURRENT_SNAPSHOT_ID=""
CONFIG_BACKUPS=()
INSTALLED_PACKAGES=(fake-pkg-three)

TARGET="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr"
rm -rf "$TARGET"

# Deploy once (nothing existed before -> "false" entry)
deploy_config_dir hypr

save_snapshot

SNAPSHOT_ID="$LAST_SNAPSHOT_ID"

# Config entry should be recorded correctly
CONFIGS_OUT="$(snapshot_configs "$SNAPSHOT_ID")"
assert_equals "hypr:false" "$CONFIGS_OUT"

assert_true test -d "$TARGET"

# Rolling back should remove the newly-deployed dir entirely (it didn't exist before)
rollback_snapshot "$SNAPSHOT_ID" >/dev/null

assert_false test -d "$TARGET"
assert_false snapshot_exists "$SNAPSHOT_ID"

echo "Snapshot/rollback OK."
