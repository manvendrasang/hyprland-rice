#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TEST_ROOT="$(mktemp -d)"

cp -r "$ROOT_DIR/modules" "$TEST_ROOT/"
cp -r "$ROOT_DIR/profiles" "$TEST_ROOT/"
cp -r "$ROOT_DIR/config" "$TEST_ROOT/"

export HYPRX_MODULES="$TEST_ROOT/modules"
export HYPRX_PROFILES="$TEST_ROOT/profiles"
export HYPRX_CONFIG="$TEST_ROOT/config"
export HYPRX_SNAPSHOT_DIR="$TEST_ROOT/state/snapshots"
export HYPRX_FAILURE_LOG="$TEST_ROOT/state/hyprx-install.log"
export HYPRX_REPORT_FILE="$TEST_ROOT/state/HyprX-Install-Report.txt"

echo "$TEST_ROOT"