#!/usr/bin/env bash

hyprx_ui_section "HyprX"

cat <<EOF
Usage:
    hyprx <command> [args]

Commands:
    install     Install packages and deploy configs
    update      Update installed packages
    rollback    Undo a previous install
    clean       Clean up temporary/cache files
    config      Read and change settings in hyprx.conf
    doctor      Diagnose system health
    help        Show this help message

Detailed usage:
    hyprx install --dry-run        Run every stage and report what would
                                   change, without installing anything

    hyprx rollback list           Show available snapshots
    hyprx rollback latest         Roll back the most recent install
    hyprx rollback <snapshot-id>  Roll back a specific snapshot

    hyprx clean                   Clean package cache, orphaned
                                   packages, screenshots older than
                                   2 days, and thumbnail/shader caches
    hyprx clean --dry-run         Preview what 'hyprx clean' would
                                   remove, without deleting anything

    hyprx config list             Show every setting and its value
    hyprx config get <KEY>        Print one value
    hyprx config set <KEY> <VAL>  Change a value (validated)
    hyprx config unset <KEY>      Restore a key to its default

    hyprx doctor --help           Diagnose system health
    hyprx config --help           Full list of settings
EOF
