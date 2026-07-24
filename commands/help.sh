#!/usr/bin/env bash

section "HyprX"

cat <<EOF
Usage:
    hyprx <command> [args]

Commands:
    install     Install modules for a profile
    update      Update installed modules
    clean       Clean up temporary/cache files
    doctor      Diagnose system and module health
    profile     Manage installation profiles
    help        Show this help message
EOF
