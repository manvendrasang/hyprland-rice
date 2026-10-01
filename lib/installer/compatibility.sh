#!/usr/bin/env bash

hyprx_compatibility_check() {

    hyprx_ui_header

    hyprx_ui_info "Checking system compatibility..."

    local failed=false

    ########################################
    # Distribution
    ########################################

    if [[ ! -f /etc/arch-release ]]; then

        hyprx_ui_error "Unsupported distribution."

        failed=true

    else

        hyprx_ui_success "Arch Linux"

    fi

    ########################################
    # Package manager
    ########################################

    if [[ "$HYPRX_DETECT_PACKAGE_MANAGER" == "unknown" ]]; then

        hyprx_ui_error "No supported package manager."

        failed=true

    else

        hyprx_ui_success "Package manager: $HYPRX_DETECT_PACKAGE_MANAGER"

    fi

    ########################################
    # Internet
    ########################################

    if ping -c1 -W2 archlinux.org >/dev/null 2>&1; then

        hyprx_ui_success "Internet connection"

    else

        hyprx_ui_warn "Internet unavailable"

    fi

    ########################################
    # Sudo
    ########################################

    if sudo -v >/dev/null 2>&1; then

        hyprx_ui_success "Sudo access"

    elif hyprx_util_dry_run; then

        # See preflight.sh: `sudo -v` cannot prompt without a TTY, and a
        # dry run never escalates, so don't fail the preview on it.

        hyprx_ui_warn "Sudo unavailable (not required for a dry run)"

    else

        hyprx_ui_error "Sudo unavailable"

        failed=true

    fi

    ########################################
    # Session
    ########################################

    case "${XDG_SESSION_TYPE:-unknown}" in

        wayland)

            hyprx_ui_success "Wayland session"
            ;;

        x11)

            hyprx_ui_warn "X11 session"
            ;;

        *)

            hyprx_ui_warn "Unknown session"
            ;;

    esac

    ########################################
    # Disk space
    ########################################

    local free

    free=$(df --output=avail "$HOME" | tail -1)

    if (( free < 1048576 )); then

        hyprx_ui_warn "Less than 1GB free space."

    else

        hyprx_ui_success "Disk space OK"

    fi

    ########################################
    # Memory
    ########################################

    local ram

    ram=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

    if (( ram < 4096 )); then

        hyprx_ui_warn "Less than 4GB RAM."

    else

        hyprx_ui_success "Memory OK"

    fi

    ########################################
    # CPU
    ########################################

    hyprx_ui_success "CPU: $(nproc) threads"

    ########################################
    # Finish
    ########################################

    hyprx_ui_divider

    if $failed; then

        hyprx_ui_error "Compatibility check failed."

        return 1

    fi

    hyprx_ui_success "Compatibility check passed."

    return 0

}
