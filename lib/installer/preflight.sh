#!/usr/bin/env bash

# Returns 0 if the system can be installed to, 1 otherwise. Under --dry-run the
# requirements a dry run does not actually exercise (network, sudo) become
# warnings, since a non-interactive dry run has no way to satisfy them.
hyprx_preflight_check() {
    hyprx_ui_header
    hyprx_ui_success "Running Preflight Checks"
    hyprx_ui_divider

    local fail=0 free ram

    if ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
        hyprx_ui_success "Internet"
    elif hyprx_util_dry_run; then
        hyprx_ui_warn "Internet (unreachable - a real install would need this)"
    else
        hyprx_ui_error "Internet"
        fail=1
    fi

    free=$(df --output=avail / | tail -1)
    if (( free > 5242880 )); then
        hyprx_ui_success "Disk Space"
    else
        hyprx_ui_error "Disk Space (<5GB)"
        fail=1
    fi

    if [[ "$HYPRX_DETECT_PACKAGE_MANAGER" != "unknown" ]]; then
        hyprx_ui_success "$HYPRX_DETECT_PACKAGE_MANAGER detected"
    else
        hyprx_ui_error "No package manager"
        fail=1
    fi

    if [[ "${HYPRX_DETECT_HAS_HYPRLAND:-false}" == true ]]; then
        hyprx_ui_success "Hyprland"
    else
        hyprx_ui_warn "Hyprland not running"
    fi

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        hyprx_ui_success "Wayland"
    else
        hyprx_ui_warn "Not Wayland"
    fi

    ram=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)
    if (( ram >= 8 )); then
        hyprx_ui_success "${ram}GB RAM"
    else
        hyprx_ui_warn "${ram}GB RAM"
    fi

    # sudo -v needs a TTY to prompt, which a non-interactive dry run lacks.
    if sudo -v >/dev/null 2>&1; then
        hyprx_ui_success "sudo"
    elif hyprx_util_dry_run; then
        hyprx_ui_warn "sudo (unvalidated - a real install would need it)"
    else
        hyprx_ui_error "sudo"
        fail=1
    fi

    hyprx_ui_divider

    return "$fail"
}
