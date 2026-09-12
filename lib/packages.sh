#!/usr/bin/env bash

########################################
# Package Manager Detection
########################################

detect_package_manager() {

    if command -v yay >/dev/null 2>&1; then
        PACKAGE_MANAGER="yay"

    elif command -v paru >/dev/null 2>&1; then
        PACKAGE_MANAGER="paru"

    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"

    else
        PACKAGE_MANAGER="unknown"
    fi

    export PACKAGE_MANAGER
}

########################################
# Queries
########################################

package_installed() {

    pacman -Q "$1" >/dev/null 2>&1

}

package_exists_official() {

    pacman -Si "$1" >/dev/null 2>&1

}

package_exists_aur() {

    case "$PACKAGE_MANAGER" in

        yay)

            yay -Si "$1" >/dev/null 2>&1
            ;;

        paru)

            paru -Si "$1" >/dev/null 2>&1
            ;;

        *)

            return 1
            ;;

    esac

}

########################################
# Installation
########################################

install_official() {

    sudo pacman -S \
        --needed \
        --noconfirm \
        "$1"

}

install_aur() {

    case "$PACKAGE_MANAGER" in

        yay)

            yay -S \
                --needed \
                --noconfirm \
                "$1"
            ;;

        paru)

            paru -S \
                --needed \
                --noconfirm \
                "$1"
            ;;

        *)

            return 1
            ;;

    esac

}

########################################
# Main installer
########################################

install_package() {

    local pkg="$1"

    ####################################
    # Forced replacement
    ####################################

    local replacement

    replacement="$(get_replacement "$pkg")"

    if [[ -n "$replacement" ]]; then

        info "$pkg -> $replacement"

        pkg="$replacement"

    fi

    ####################################
    # Already installed
    ####################################

    if package_installed "$pkg"; then
        return 10
    fi

    ####################################
    # Official
    ####################################

    if package_exists_official "$pkg"; then

        install_official "$pkg"

        return $?

    fi

    ####################################
    # AUR
    ####################################

    if package_exists_aur "$pkg"; then

        install_aur "$pkg"

        return $?

    fi

    ####################################
    # Failure
    ####################################

    return 1

}

########################################
# Removal
########################################

remove_package() {

    local pkg="$1"

    package_installed "$pkg" || return 0

    sudo pacman -Rns \
        --noconfirm \
        "$pkg"

}

########################################
# System Update
########################################

update_system() {

    case "$PACKAGE_MANAGER" in

        yay)

            yay -Syu --noconfirm
            ;;

        paru)

            paru -Syu --noconfirm
            ;;

        pacman)

            sudo pacman -Syu --noconfirm
            ;;

        *)

            return 1
            ;;

    esac

}

########################################
# Cache
########################################

clean_package_cache() {

    if ! command -v pacman >/dev/null 2>&1; then
        warn "pacman not found - skipping package cache clean"
        return 0
    fi

    # Interrupted/retried downloads leave stale
    # "download-<random>" temp files in the cache
    # dir. pacman's own cache-clean chokes trying
    # to read these as package archives ("could
    # not open file ...: Error reading fd 8") -
    # removing them first lets the real cache
    # clean run without errors.
    if command -v sudo >/dev/null 2>&1; then
        sudo find /var/cache/pacman/pkg -maxdepth 1 -name 'download-*' -delete 2>/dev/null
    fi

    case "$PACKAGE_MANAGER" in

        yay)
            yay -Sc --noconfirm
            ;;

        paru)
            paru -Sc --noconfirm
            ;;

        pacman)
            sudo pacman -Sc --noconfirm
            ;;

        *)
            warn "Unknown package manager - skipping cache clean"
            return 0
            ;;

    esac

}

########################################
# Orphans
########################################

list_orphan_packages() {

    command -v pacman >/dev/null 2>&1 || return 0

    pacman -Qtdq 2>/dev/null

}

remove_orphan_packages() {

    if ! command -v pacman >/dev/null 2>&1; then
        warn "pacman not found - skipping orphan package check"
        return 0
    fi

    local orphans
    mapfile -t orphans < <(list_orphan_packages)

    if ((${#orphans[@]} == 0)); then
        success "No orphan packages found."
        return 0
    fi

    printf "%s\n\n" "${orphans[@]}"

    if confirm "Remove orphan packages?"; then
        command -v sudo >/dev/null 2>&1 && sudo pacman -Rns --noconfirm "${orphans[@]}"
    fi

}

########################################
# Information
########################################

list_installed_packages() {

    pacman -Q

}

search_package() {

    pacman -Ss "$1"

}

package_info() {

    pacman -Si "$1"

}

count_installed_packages() {

    pacman -Q | wc -l

}

########################################

detect_package_manager