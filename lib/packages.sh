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

# Install many packages in as few transactions as possible.
#
# This used to be one `pacman -S` per package - roughly 50 sequential
# transactions for a full install, each one re-resolving dependencies and
# re-reading the sync databases. Batching is not just faster: a single
# transaction either applies or it does not, so a failure cannot leave half a
# dependency set installed.
#
# Official and AUR packages are kept in separate transactions because they go
# through different helpers and a failure in one must not abort the other.
# Already-installed packages are filtered out first, so re-running an install is
# a no-op rather than a full re-resolve.
#
# Returns 0 if everything that was missing is now installed, 1 otherwise.
hyprx_pkg_install_many() {
    local -a pkgs=("$@")
    local -a official=() aur=() missing=()
    local pkg

    if (( ${#pkgs[@]} == 0 )); then
        return 0
    fi

    for pkg in "${pkgs[@]}"; do
        pkg="$(hyprx_replacements_get "$pkg")"
        [[ -z "$pkg" ]] && pkg="${pkgs[0]}"

        if hyprx_pkg_installed "$pkg"; then
            continue
        fi

        if hyprx_pkg_exists_official "$pkg"; then
            official+=("$pkg")
        elif hyprx_pkg_exists_aur "$pkg"; then
            aur+=("$pkg")
        else
            # Unresolvable here means the queue was not validated. Report it
            # rather than silently dropping it from the transaction.
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        hyprx_ui_error "Cannot install: ${missing[*]}"
        return 1
    fi

    if (( ${#official[@]} > 0 )); then
        hyprx_ui_info "Installing ${#official[@]} package(s) from the official repos"
        if hyprx_util_dry_run; then
            hyprx_util_would "install (official repo) ${official[*]}"
        else
            # shellcheck disable=SC2086
            sudo pacman -S --needed --noconfirm "${official[@]}" || return 1
        fi
    fi

    if (( ${#aur[@]} > 0 )); then
        hyprx_ui_info "Installing ${#aur[@]} package(s) from the AUR"
        if hyprx_util_dry_run; then
            hyprx_util_would "install (AUR via $HYPRX_DETECT_PACKAGE_MANAGER) ${aur[*]}"
        else
            case "$HYPRX_DETECT_PACKAGE_MANAGER" in
                yay)  yay -S --needed --noconfirm "${aur[@]}" || return 1 ;;
                paru) paru -S --needed --noconfirm "${aur[@]}" || return 1 ;;
                *)    hyprx_ui_error "No AUR helper for: ${aur[*]}"; return 1 ;;
            esac
        fi
    fi

    return 0
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
