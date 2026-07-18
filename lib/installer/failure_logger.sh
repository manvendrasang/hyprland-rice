#!/usr/bin/env bash

FAILURE_LOG="$HOME/Desktop/hyprx-install.log"

touch "$FAILURE_LOG"

log_failed_package() {

    local pkg="$1"
    local reason="${2:-Unknown}"

    {
        echo "=========================================================="
        echo "Timestamp : $(date)"
        echo "Package   : $pkg"
        echo "Reason    : $reason"
        echo "Manager   : ${PACKAGE_MANAGER:-Unknown}"
        echo "Session   : ${XDG_SESSION_TYPE:-Unknown}"
        echo "Host      : $(hostname)"
        echo "Kernel    : $(uname -r)"
        echo
    } >>"$FAILURE_LOG"

}

log_failure_summary() {

    {
        echo
        echo "=========================================================="
        echo "Failure Summary"
        echo "=========================================================="
        echo

        printf "Failed Packages : %d\n" "${#FAILED_PACKAGES[@]}"
        printf "Installed       : %d\n" "${#INSTALLED_PACKAGES[@]}"
        printf "Skipped         : %d\n" "${#SKIPPED_PACKAGES[@]}"

        echo

        if (( ${#FAILED_PACKAGES[@]} > 0 )); then
            echo "Packages"

            for pkg in "${FAILED_PACKAGES[@]}"; do
                echo "  • $pkg"
            done
        else
            echo "No remaining failures."
        fi

        echo
        echo "=========================================================="

    } >>"$FAILURE_LOG"

}