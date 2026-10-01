#!/usr/bin/env bash

# shellcheck disable=SC1090

HYPRX_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPRX_ROOT="$(dirname "$HYPRX_BOOTSTRAP_DIR")"

export HYPRX_ROOT
export HYPRX_LIB="$HYPRX_ROOT/lib"
export HYPRX_COMMANDS="$HYPRX_ROOT/commands"
export HYPRX_DATABASE="$HYPRX_ROOT/database"
export HYPRX_CONFIG="${HYPRX_CONFIG:-$HYPRX_ROOT/config}"


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
    spinner.sh \
    progress.sh \
    table.sh
do
    source "$HYPRX_LIB/$file"
done

#
# Installer libraries
#

for file in \
    replacements.sh \
    requirements.sh \
    failure_logger.sh \
    retry.sh \
    recovery.sh \
    resolver.sh \
    validator.sh \
    compatibility.sh \
    preflight.sh \
    install_packages.sh \
    snapshot.sh \
    deploy.sh \
    report.sh \
    engine.sh
do
    source "$HYPRX_LIB/installer/$file"
done

export HYPRX_INITIALIZED=true
