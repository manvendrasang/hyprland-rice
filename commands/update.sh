#!/usr/bin/env bash

hyprx_ui_header
hyprx_logger_info "Starting system update"

start_time=$(date +%s)

hyprx_ui_info "Synchronizing package databases..."

case "$HYPRX_DETECT_PACKAGE_MANAGER" in
    yay)
        yay -Syu
        ;;
    paru)
        paru -Syu
        ;;
    pacman)
        sudo pacman -Syu
        ;;
    *)
        hyprx_ui_error "Unsupported package manager: $HYPRX_DETECT_PACKAGE_MANAGER"
        exit 1
        ;;
esac

echo

hyprx_ui_info "Refreshing package database..."

case "$HYPRX_DETECT_PACKAGE_MANAGER" in
    yay)
        yay -Sy >/dev/null
        ;;
    paru)
        paru -Sy >/dev/null
        ;;
    pacman)
        sudo pacman -Sy >/dev/null
        ;;
esac

echo

hyprx_ui_info "Checking for orphan packages..."

hyprx_pkg_remove_orphans

echo

hyprx_ui_info "Updating package cache..."

hyprx_pkg_clean_cache

echo

hyprx_ui_divider

end_time=$(date +%s)
elapsed=$((end_time - start_time))

hyprx_ui_success "System update completed."
hyprx_logger_success "System update completed successfully."

echo
printf "%-20s %ss\n" "Elapsed" "$elapsed"
