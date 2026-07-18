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

orphans="$(pacman -Qdtq 2>/dev/null || true)"

if [[ -n "$orphans" ]]; then

    printf "%s\n\n" "$orphans"

    if confirm "Remove orphan packages?"; then
        sudo pacman -Rns --noconfirm $orphans
    fi

else

    success "No orphan packages found."

fi

echo

info "Updating package cache..."

case "$PACKAGE_MANAGER" in
    yay)
        yay -Sc --noconfirm >/dev/null
        ;;
    paru)
        paru -Sc --noconfirm >/dev/null
        ;;
    pacman)
        sudo pacman -Sc --noconfirm >/dev/null
        ;;
esac

echo

divider

end_time=$(date +%s)
elapsed=$((end_time - start_time))

success "System update completed."
success_log "System update completed successfully."

echo
printf "%-20s %ss\n" "Elapsed" "$elapsed"