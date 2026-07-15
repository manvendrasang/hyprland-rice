#!/usr/bin/env bash

export HYPRX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/installer/compatibility.sh"
export HYPRX_LIB="$HYPRX_ROOT/lib"
export HYPRX_COMMANDS="$HYPRX_ROOT/commands"
export HYPRX_MODULES="$HYPRX_ROOT/modules"
export HYPRX_DATABASE="$HYPRX_ROOT/database"
export HYPRX_CONFIG="$HYPRX_ROOT/config"

for file in \
  ui.sh \
  utils.sh \
  logger.sh \
  config.sh \
  detect.sh \
  packages.sh \
  modules.sh \
  spinner.sh \
  progress.sh \
  table.sh; do
  source "$HYPRX_LIB/$file"
done

for file in \
  engine.sh \
  preflight.sh \
  resolver.sh \
  installer.sh \
  validator.sh \
  report.sh \
  recovery.sh \
  rollback.sh; do
  source "$HYPRX_LIB/installer/$file"
done

export HYPRX_INITIALIZED=true
