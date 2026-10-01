#!/usr/bin/env bash

HYPRX_FAILURE_LOG="${HYPRX_FAILURE_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/hyprx-install.log}"

mkdir -p "$(dirname "$HYPRX_FAILURE_LOG")"
touch "$HYPRX_FAILURE_LOG"

hyprx_failure_logger_log() {

    local pkg="$1"
    local reason="${2:-Unknown}"

    {
        echo "=========================================================="
        echo "Timestamp : $(date)"
        echo "Package   : $pkg"
        echo "Reason    : $reason"
        echo "Manager   : ${HYPRX_DETECT_PACKAGE_MANAGER:-Unknown}"
        echo "Session   : ${XDG_SESSION_TYPE:-Unknown}"
        echo "Host      : $(hostname)"
        echo "Kernel    : $(uname -r)"
        echo
    } >>"$HYPRX_FAILURE_LOG"

}

hyprx_failure_logger_summary() {

    {
        echo
        echo "=========================================================="
        echo "Failure Summary"
        echo "=========================================================="
        echo

        printf "Failed Packages : %d\n" "${#HYPRX_INSTALL_FAILED[@]}"
        printf "Installed       : %d\n" "${#HYPRX_INSTALL_INSTALLED[@]}"
        printf "Skipped         : %d\n" "${#HYPRX_INSTALL_SKIPPED[@]}"

        echo

        if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then
            echo "Packages"

            for pkg in "${HYPRX_INSTALL_FAILED[@]}"; do
                echo "  • $pkg"
            done
        else
            echo "No remaining failures."
        fi

        echo

        echo "=========================================================="

    } >>"$HYPRX_FAILURE_LOG"

}
