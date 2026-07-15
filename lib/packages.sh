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

    sudo pacman -Sc --noconfirm

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