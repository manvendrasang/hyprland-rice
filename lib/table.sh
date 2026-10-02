#!/usr/bin/env bash

hyprx_table_header() {
    printf "\n"
    printf "%-28s %-18s\n" "Item" "Value"
    printf "%-28s %-18s\n" \
    "────────────────────────────" \
    "──────────────────"
}

hyprx_table_row() {
    printf "%-28s %-18s\n" "$1" "$2"
}
