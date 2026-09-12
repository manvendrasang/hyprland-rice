#!/usr/bin/env bash

header
info_log "Starting system update"

start_time=$(date +%s)

info "Synchronizing package databases..."

case "$PACKAGE_MANAGER" in
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
        error "Unsupported package manager: $PACKAGE_MANAGER"
        exit 1
        ;;
esac

echo

info "Refreshing package database..."

case "$PACKAGE_MANAGER" in
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

info "Checking for orphan packages..."

remove_orphan_packages

echo

info "Updating package cache..."

clean_package_cache

echo

divider

end_time=$(date +%s)
elapsed=$((end_time - start_time))

success "System update completed."
success_log "System update completed successfully."

echo
printf "%-20s %ss\n" "Elapsed" "$elapsed"