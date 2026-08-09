#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TEST_ROOT="$(mktemp -d)"

cp -r "$ROOT_DIR/config" "$TEST_ROOT/"

export HYPRX_CONFIG="$TEST_ROOT/config"
export HYPRX_SNAPSHOT_DIR="$TEST_ROOT/state/snapshots"
export HYPRX_FAILURE_LOG="$TEST_ROOT/state/hyprx-install.log"
export HYPRX_REPORT_FILE="$TEST_ROOT/state/HyprX-Install-Report.txt"
export HYPRX_TARGET_HOME="$TEST_ROOT/home"
export HYPRX_CONFIG_BACKUP_ROOT="$TEST_ROOT/state/config-backups"

mkdir -p "$HYPRX_TARGET_HOME/.config"

echo "$TEST_ROOT"