#!/usr/bin/env bash

section "HyprX"

cat <<EOF
Usage:
    hyprx <command> [args]

Commands:
    install     Install packages and deploy configs
    update      Update installed packages
    rollback    Undo a previous install
    clean       Clean up temporary/cache files
    doctor      Diagnose system health
    help        Show this help message
EOF
