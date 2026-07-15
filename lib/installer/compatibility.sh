#!/usr/bin/env bash

check_compatibility() {

    header

    info "Checking system compatibility..."

    local failed=false

    ########################################
    # Distribution
    ########################################

    if [[ ! -f /etc/arch-release ]]; then

        error "Unsupported distribution."

        failed=true

    else

        success "Arch Linux"

    fi

    ########################################
    # Package manager
    ########################################

    if [[ "$PACKAGE_MANAGER" == "unknown" ]]; then

        error "No supported package manager."

        failed=true

    else

        success "Package manager: $PACKAGE_MANAGER"

    fi

    ########################################
    # Internet
    ########################################

    if ping -c1 -W2 archlinux.org >/dev/null 2>&1; then

        success "Internet connection"

    else

        warn "Internet unavailable"

    fi

    ########################################
    # Sudo
    ########################################

    if sudo -v >/dev/null 2>&1; then

        success "Sudo access"

    else

        error "Sudo unavailable"

        failed=true

    fi

    ########################################
    # Session
    ########################################

    case "${XDG_SESSION_TYPE:-unknown}" in

        wayland)

            success "Wayland session"
            ;;

        x11)

            warn "X11 session"
            ;;

        *)

            warn "Unknown session"
            ;;

    esac

    ########################################
    # Disk space
    ########################################

    local free

    free=$(df --output=avail "$HOME" | tail -1)

    if (( free < 1048576 )); then

        warn "Less than 1GB free space."

    else

        success "Disk space OK"

    fi

    ########################################
    # Memory
    ########################################

    local ram

    ram=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

    if (( ram < 4096 )); then

        warn "Less than 4GB RAM."

    else

        success "Memory OK"

    fi

    ########################################
    # CPU
    ########################################

    success "CPU: $(nproc) threads"

    ########################################
    # Finish
    ########################################

    divider

    if $failed; then

        error "Compatibility check failed."

        return 1

    fi

    success "Compatibility check passed."

    return 0

}