#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

export ROOT_DIR

source "$ROOT_DIR/lib/bootstrap.sh"

COMMAND="${1:-help}"
shift || true

COMMAND_FILE="$HYPRX_COMMANDS/$COMMAND.sh"

if [[ ! -f "$COMMAND_FILE" ]]; then
    error "Unknown command: $COMMAND"
    echo
    info "Available commands:"
    find "$HYPRX_COMMANDS" -maxdepth 1 -type f -name "*.sh" \
        -printf "%f\n" | sed 's/\.sh$//' | sort
    exit 1
fi

source "$COMMAND_FILE"