#!/usr/bin/env bash

hyprx_pkg_detect_manager() {
    # An explicit PACKAGE_MANAGER in hyprx.conf wins over auto-detection.
    local configured="${HYPRX_CONFIG_PACKAGE_MANAGER:-auto}"

    case "$configured" in
        pacman|yay|paru)
            if command -v "$configured" >/dev/null 2>&1; then
                HYPRX_DETECT_PACKAGE_MANAGER="$configured"
                export HYPRX_DETECT_PACKAGE_MANAGER
                return 0
            fi
            hyprx_ui_warn "PACKAGE_MANAGER=$configured is configured but not installed - falling back to auto"
            ;;
    esac

    if command -v yay >/dev/null 2>&1; then
        HYPRX_DETECT_PACKAGE_MANAGER="yay"
    elif command -v paru >/dev/null 2>&1; then
        HYPRX_DETECT_PACKAGE_MANAGER="paru"
    elif command -v pacman >/dev/null 2>&1; then
        HYPRX_DETECT_PACKAGE_MANAGER="pacman"
    else
        HYPRX_DETECT_PACKAGE_MANAGER="unknown"
    fi

    export HYPRX_DETECT_PACKAGE_MANAGER
}

hyprx_pkg_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

hyprx_pkg_exists_official() {
    pacman -Si "$1" >/dev/null 2>&1
}

hyprx_pkg_exists_aur() {
    case "$HYPRX_DETECT_PACKAGE_MANAGER" in
        yay)  yay -Si "$1" >/dev/null 2>&1 ;;
        paru) paru -Si "$1" >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

hyprx_pkg_install_official() {
    if hyprx_util_dry_run; then
        hyprx_util_would "install (official repo) $1"
        return 0
    fi

    sudo pacman -S --needed --noconfirm "$1"
}

hyprx_pkg_install_aur() {
    if hyprx_util_dry_run; then
        hyprx_util_would "install (AUR via $HYPRX_DETECT_PACKAGE_MANAGER) $1"
        return 0
    fi

    case "$HYPRX_DETECT_PACKAGE_MANAGER" in
        yay)  yay -S --needed --noconfirm "$1" ;;
        paru) paru -S --needed --noconfirm "$1" ;;
        *)    return 1 ;;
    esac
}

# Returns 0 installed, 10 already present, 1 failed.
hyprx_pkg_install() {
    local pkg="$1" replacement

    replacement="$(hyprx_replacements_get "$pkg")"
    if [[ -n "$replacement" ]]; then
        hyprx_ui_info "$pkg -> $replacement"
        pkg="$replacement"
    fi

    if hyprx_pkg_installed "$pkg"; then
        return 10
    fi

    if hyprx_pkg_exists_official "$pkg"; then
        hyprx_pkg_install_official "$pkg"
        return $?
    fi

    if hyprx_pkg_exists_aur "$pkg"; then
        hyprx_pkg_install_aur "$pkg"
        return $?
    fi

    return 1
}

hyprx_pkg_remove() {
    local pkg="$1"

    hyprx_pkg_installed "$pkg" || return 0

    sudo pacman -Rns --noconfirm "$pkg"
}

# The single place the yay/paru/pacman dispatch lives.
hyprx_pkg_update_system() {
    case "$HYPRX_DETECT_PACKAGE_MANAGER" in
        yay)  yay -Syu --noconfirm ;;
        paru) paru -Syu --noconfirm ;;
        pacman) sudo pacman -Syu --noconfirm ;;
        *)    return 1 ;;
    esac
}

hyprx_pkg_clean_cache() {
    if ! command -v pacman >/dev/null 2>&1; then
        hyprx_ui_warn "pacman not found - skipping package cache clean"
        return 0
    fi

    # Interrupted downloads leave "download-<random>" files that make pacman's
    # own cache clean fail with "could not open file ...: Error reading fd 8".
    if command -v sudo >/dev/null 2>&1; then
        sudo find /var/cache/pacman/pkg -maxdepth 1 -name 'download-*' -delete 2>/dev/null
    fi

    case "$HYPRX_DETECT_PACKAGE_MANAGER" in
        yay)  yay -Sc --noconfirm ;;
        paru) paru -Sc --noconfirm ;;
        pacman) sudo pacman -Sc --noconfirm ;;
        *)
            hyprx_ui_warn "Unknown package manager - skipping cache clean"
            return 0
            ;;
    esac
}

hyprx_pkg_list_orphans() {
    command -v pacman >/dev/null 2>&1 || return 0

    pacman -Qtdq 2>/dev/null
}

hyprx_pkg_remove_orphans() {
    if ! command -v pacman >/dev/null 2>&1; then
        hyprx_ui_warn "pacman not found - skipping orphan package check"
        return 0
    fi

    local orphans
    mapfile -t orphans < <(hyprx_pkg_list_orphans)

    if ((${#orphans[@]} == 0)); then
        hyprx_ui_success "No orphan packages found."
        return 0
    fi

    printf "%s\n\n" "${orphans[@]}"

    if hyprx_util_confirm "Remove orphan packages?"; then
        command -v sudo >/dev/null 2>&1 && sudo pacman -Rns --noconfirm "${orphans[@]}"
    fi
}

hyprx_pkg_detect_manager
