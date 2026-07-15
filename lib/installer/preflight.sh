#!/usr/bin/env bash

preflight() {

    header

    success "Running Preflight Checks"

    divider

    FAIL=0

    ####################################
    # Internet
    ####################################

    if ping -c1 archlinux.org >/dev/null 2>&1; then
        success "Internet"
    else
        error "Internet"
        FAIL=1
    fi

    ####################################
    # Disk
    ####################################

    FREE=$(df --output=avail / | tail -1)

    if (( FREE > 5242880 )); then
        success "Disk Space"
    else
        error "Disk Space (<5GB)"
        FAIL=1
    fi

    ####################################
    # Package Manager
    ####################################

    [[ -n "$PACKAGE_MANAGER" ]] \
        && success "$PACKAGE_MANAGER detected" \
        || {
            error "No package manager"
            FAIL=1
        }

    ####################################
    # Hyprland
    ####################################

    [[ "$HAS_HYPRLAND" == true ]] \
        && success "Hyprland" \
        || warn "Hyprland not running"

    ####################################
    # Wayland
    ####################################

    [[ "$XDG_SESSION_TYPE" == wayland ]] \
        && success "Wayland" \
        || warn "Not Wayland"

    ####################################
    # RAM
    ####################################

    RAM=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)

    if (( RAM >= 8 )); then
        success "${RAM}GB RAM"
    else
        warn "${RAM}GB RAM"
    fi

    ####################################
    # Root
    ####################################

    if sudo -v >/dev/null 2>&1; then
        success "sudo"
    else
        error "sudo"
        FAIL=1
    fi

    divider

    return "$FAIL"

}