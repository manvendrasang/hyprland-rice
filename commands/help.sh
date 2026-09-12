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

Detailed usage:
    hyprx rollback list           Show available snapshots
    hyprx rollback latest         Roll back the most recent install
    hyprx rollback <snapshot-id>  Roll back a specific snapshot

    hyprx clean                   Clean package cache, orphaned
                                   packages, screenshots older than
                                   2 days, and thumbnail/shader caches
    hyprx clean --dry-run         Preview what 'hyprx clean' would
                                   remove, without deleting anything
EOF
