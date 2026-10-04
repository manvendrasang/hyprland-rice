#!/usr/bin/env bash

hyprx_util_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Set by `hyprx install --dry-run` / `hyprx clean --dry-run`. Every mutating
# helper checks this before touching anything.
hyprx_util_dry_run() {
    [[ "${HYPRX_DRY_RUN:-0}" == "1" ]]
}

hyprx_util_would() {
    hyprx_ui_info "[${HYPRX_REPORT_PREFIX:-dry-run}] Would $*"
}

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

# AUTO_CONFIRM=true answers yes. Only for destructive steps the caller has
# already decided on, never to gather information.
hyprx_util_confirm() {
    hyprx_config_bool HYPRX_CONFIG_AUTO_CONFIRM && return 0

    local answer
    read -rp "$1 [Y/n]: " answer

    case "$answer" in
        [Nn]*) return 1 ;;
        *) return 0 ;;
    esac
}

hyprx_util_validate_package_name() {
    local pkg="$1"
    [[ "$pkg" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]
}

hyprx_util_validate_snapshot_id() {
    local id="$1"
    # The trailing -<nanoseconds> is part of the id since snapshot IDs gained
    # sub-second resolution; without it every real id reads as malformed.
    [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]]
}
