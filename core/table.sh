#!/usr/bin/env bash

table_header() {

    printf "\n"

    printf "%-28s %-18s\n" "Item" "Value"

    printf "%-28s %-18s\n" \
    "────────────────────────────" \
    "──────────────────"
}

table_row() {

    printf "%-28s %-18s\n" "$1" "$2"

}