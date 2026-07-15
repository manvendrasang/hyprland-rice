#!/usr/bin/env bash

CONFIG_FILE="$ROOT_DIR/config/hyprx.conf"

[[ -f "$CONFIG_FILE" ]] || {
    echo "Missing configuration:"
    echo "$CONFIG_FILE"
    exit 1
}

source "$CONFIG_FILE"