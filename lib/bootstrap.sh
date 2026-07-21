#!/usr/bin/env bash

# shellcheck disable=SC1090

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$BOOTSTRAP_DIR")"

export ROOT_DIR
export HYPRX_ROOT="$ROOT_DIR"

export HYPRX_LIB="$ROOT_DIR/lib"
export HYPRX_COMMANDS="$ROOT_DIR/commands"
export HYPRX_MODULES="$ROOT_DIR/modules"
export HYPRX_DATABASE="$ROOT_DIR/database"
export HYPRX_CONFIG="$ROOT_DIR/config"
export HYPRX_PROFILES="$ROOT_DIR/profiles"
export HYPRX_THEMES="$ROOT_DIR/themes"
export HYPRX_ASSETS="$ROOT_DIR/assets"

#
# Core libraries
#

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
    table.sh
do
    source "$HYPRX_LIB/$file"
done

#
# Module libraries
#

source "$HYPRX_LIB/module/module.sh"

#
# Profile libraries
#

for file in \
    profile.sh \
    validator.sh
do
    source "$HYPRX_LIB/profile/$file"
done

#
# Installer libraries
#

for file in \
    replacements.sh \
    failure_logger.sh \
    retry.sh \
    recovery.sh \
    resolver.sh \
    validator.sh \
    compatibility.sh \
    preflight.sh \
    install_packages.sh \
    report.sh \
    engine.sh
do
    source "$HYPRX_LIB/installer/$file"
done

export HYPRX_INITIALIZED=true