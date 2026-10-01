#!/usr/bin/env bash

hyprx_preflight_check() {

    hyprx_ui_header

    hyprx_ui_success "Running Preflight Checks"

    hyprx_ui_divider

    local fail=0
    local free
    local ram

    ####################################
    # Internet
    ####################################

    if ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
        hyprx_ui_success "Internet"
    elif hyprx_util_dry_run; then
        # A dry run downloads nothing, so an unreachable network is worth
        # reporting but must not abort the preview. The real run will fail
        # here, which is exactly what should happen.
        hyprx_ui_warn "Internet (unreachable - a real install would need this)"
    else
        hyprx_ui_error "Internet"
        fail=1
    fi

    ####################################
    # Disk
    ####################################

    free=$(df --output=avail / | tail -1)

    if (( free > 5242880 )); then
        hyprx_ui_success "Disk Space"
    else
        hyprx_ui_error "Disk Space (<5GB)"
        fail=1
    fi

    ####################################
    # Package Manager
    ####################################

    if [[ "$HYPRX_DETECT_PACKAGE_MANAGER" != "unknown" ]]; then
        hyprx_ui_success "$HYPRX_DETECT_PACKAGE_MANAGER detected"
    else
        hyprx_ui_error "No package manager"
        fail=1
    fi

    ####################################
    # Hyprland
    ####################################

    if [[ "${HYPRX_DETECT_HAS_HYPRLAND:-false}" == true ]]; then
        hyprx_ui_success "Hyprland"
    else
        hyprx_ui_warn "Hyprland not running"
    fi

    ####################################
    # Wayland
    ####################################

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        hyprx_ui_success "Wayland"
    else
        hyprx_ui_warn "Not Wayland"
    fi

    ####################################
    # RAM
    ####################################

    ram=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)

    if (( ram >= 8 )); then
        hyprx_ui_success "${ram}GB RAM"
    else
        hyprx_ui_warn "${ram}GB RAM"
    fi

    ####################################
    # Root
    ####################################

    if sudo -v >/dev/null 2>&1; then
        hyprx_ui_success "sudo"
    elif hyprx_util_dry_run; then
        # `sudo -v` needs a TTY to prompt. A dry run invoked
        # non-interactively (test suite, CI) has no way to authenticate and
        # never escalates anyway, so this is informational.
        hyprx_ui_warn "sudo (unvalidated - a real install would need it)"
    else
        hyprx_ui_error "sudo"
        fail=1
    fi

    hyprx_ui_divider

    return "$fail"

}
