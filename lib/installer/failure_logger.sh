#!/usr/bin/env bash

# lib/config.sh runs earlier in the bootstrap order and exports
# HYPRX_FAILURE_LOG_OVERRIDE when HYPRX_CONFIG_LOG_FILE is set. That line used
# to overwrite it unconditionally, so LOG_FILE was silently ignored: the config
# comment claimed "Honoured here because config.sh is sourced before
# failure_logger.sh" and the unconditional assignment defeated it on the very
# next line.
#
# Precedence: HYPRX_CONFIG_LOG_FILE > HYPRX_FAILURE_LOG_OVERRIDE (env) > state dir.
#
# The name carries an _OVERRIDE suffix because lib/state.sh reads it under that
# name. This used to assign HYPRX_FAILURE_LOG - the pre-rename override name -
# which nothing reads any more, so the assignment was silently doing nothing.
if [[ -z "${HYPRX_FAILURE_LOG_OVERRIDE:-}" ]]; then
    HYPRX_FAILURE_LOG_OVERRIDE="$HYPRX_STATE_FAILURE_LOG"
fi

mkdir -p "$(dirname "$HYPRX_FAILURE_LOG_OVERRIDE")" 2>/dev/null || true
touch "$HYPRX_FAILURE_LOG_OVERRIDE" 2>/dev/null || true

# `hostname` comes from inetutils, which packages.list now installs - but this
# function runs in whatever environment a failure happened in, including a
# minimal container, and it used to print "hostname: command not found" into
# the failure log while recording the failure. hostnamectl is the systemd
# equivalent and uname -n is the portable fallback, so there is always an answer.
hyprx_failure_logger_host() {
    if command -v hostname >/dev/null 2>&1; then
        hostname 2>/dev/null && return 0
    fi
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl --static 2>/dev/null && return 0
    fi
    uname -n 2>/dev/null && return 0
    printf 'unknown'
}

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
        echo "Host      : $(hyprx_failure_logger_host)"
        echo "Kernel    : $(uname -r)"
        echo
    } >>"$HYPRX_FAILURE_LOG_OVERRIDE"
}

hyprx_failure_logger_summary() {
    local pkg

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
    } >>"$HYPRX_FAILURE_LOG_OVERRIDE"
}
