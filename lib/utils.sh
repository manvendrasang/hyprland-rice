#!/usr/bin/env bash

########################################
# Generic Helpers
########################################

hyprx_util_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

hyprx_util_is_root() {
    [[ $EUID -eq 0 ]]
}

hyprx_util_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

########################################
# Dry run
########################################

# True when the current run must not mutate the system. Set by
# `hyprx install --dry-run` / `hyprx clean --dry-run`; every mutating
# helper checks this before touching anything.
hyprx_util_dry_run() {
    [[ "${HYPRX_DRY_RUN:-0}" == "1" ]]
}

# Print the standard "[dry-run] would ..." prefix, so output reads the
# same regardless of which command emitted it.
hyprx_util_would() {
    hyprx_ui_info "[dry-run] Would $*"
}

########################################
# Size
########################################

hyprx_util_bytes_to_human() {

    local bytes=$1

    if (( bytes >= 1073741824 )); then
        awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}"
    elif (( bytes >= 1024 )); then
        awk "BEGIN {printf \"%.2f KB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi

}

########################################
# Confirmation
########################################

hyprx_util_confirm() {

    local answer

    read -rp "$1 [Y/n]: " answer

    case "$answer" in
        [Nn]*) return 1 ;;
        *) return 0 ;;
    esac

}

########################################
# Input validation
########################################

hyprx_util_validate_package_name() {
    local pkg="$1"
    [[ "$pkg" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]
}

hyprx_util_validate_snapshot_id() {
    local id="$1"
    [[ "$id" =~ ^[0-9]{8}-[0-9]{6}$ ]]
}

########################################
# Disk Usage
########################################

hyprx_util_directory_size() {

    du -sb "$1" 2>/dev/null | awk '{print $1}'

}
