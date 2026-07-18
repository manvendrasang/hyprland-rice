#!/usr/bin/env bash

preflight() {

    header

    success "Running Preflight Checks"

    divider

    local fail=0
    local free
    local ram

    ####################################
    # Internet
    ####################################

    if ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
        success "Internet"
    else
        error "Internet"
        fail=1
    fi

    ####################################
    # Disk
    ####################################

    free=$(df --output=avail / | tail -1)

    if (( free > 5242880 )); then
        success "Disk Space"
    else
        error "Disk Space (<5GB)"
        fail=1
    fi

    ####################################
    # Package Manager
    ####################################

    if [[ "$PACKAGE_MANAGER" != "unknown" ]]; then
        success "$PACKAGE_MANAGER detected"
    else
        error "No package manager"
        fail=1
    fi

    ####################################
    # Hyprland
    ####################################

    [[ "${HAS_HYPRLAND:-false}" == true ]] \
        && success "Hyprland" \
        || warn "Hyprland not running"

    ####################################
    # Wayland
    ####################################

    [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] \
        && success "Wayland" \
        || warn "Not Wayland"

    ####################################
    # RAM
    ####################################

    ram=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)

    if (( ram >= 8 )); then
        success "${ram}GB RAM"
    else
        warn "${ram}GB RAM"
    fi

    ####################################
    # Root
    ####################################

    if sudo -v >/dev/null 2>&1; then
        success "sudo"
    else
        error "sudo"
        fail=1
    fi

    divider

    return "$fail"

}