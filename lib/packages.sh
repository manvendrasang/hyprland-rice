#!/usr/bin/env bash

install_package() {

    local package="$1"
    local source="$2"

    case "$source" in

        official)

            sudo pacman -S --needed --noconfirm "$package"

            ;;

        aur)

            if command -v yay >/dev/null; then

                yay -S --needed --noconfirm "$package"

            elif command -v paru >/dev/null; then

                paru -S --needed --noconfirm "$package"

            else

                return 10

            fi

            ;;

        flatpak)

            flatpak install -y flathub "$package"

            ;;

        cargo)

            cargo install "$package"

            ;;

        go)

            go install "$package"

            ;;

        npm)

            npm install -g "$package"

            ;;

        pipx)

            pipx install "$package"

            ;;

        github)

            return 20

            ;;

        *)

            return 99

            ;;

    esac

}