#!/usr/bin/env bash

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
COMMAND_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(dirname "$COMMAND_DIR")"

source "$ROOT_DIR/core/ui.sh"
source "$ROOT_DIR/core/utils.sh"
source "$ROOT_DIR/core/logger.sh"
source "$ROOT_DIR/core/detect.sh"

header

info_log "Update started"

MODE="normal"

[[ "$1" == "--yes" ]] && MODE="yes"
[[ "$1" == "--check" ]] && MODE="check"

echo

info "Checking updates..."

case "$PACKAGE_MANAGER" in

    yay)

        UPDATES=$(yay -Qu 2>/dev/null)

        ;;

    paru)

        UPDATES=$(paru -Qu 2>/dev/null)

        ;;

    pacman)

        UPDATES=$(checkupdates 2>/dev/null)

        ;;

    *)

        error "No supported package manager."

        exit 1

        ;;

esac

COUNT=$(echo "$UPDATES" | grep -c .)

success "$COUNT package(s) available."

echo

if [[ "$COUNT" -gt 0 ]]; then

    echo "$UPDATES"

fi

echo

if [[ "$MODE" == "check" ]]; then

    exit 0

fi

if [[ "$MODE" != "yes" ]]; then

    confirm "Install updates?"

    [[ $? -ne 0 ]] && exit 0

fi

START=$(date +%s)

case "$PACKAGE_MANAGER" in

    yay)

        yay -Syu

        ;;

    paru)

        paru -Syu

        ;;

    pacman)

        sudo pacman -Syu

        ;;

esac

echo

info "Cleaning package cache..."

sudo paccache -r

END=$(date +%s)

echo

divider

success "Update completed."

printf "%-20s %ss\n" "Elapsed" "$((END-START))"

success_log "Update completed"