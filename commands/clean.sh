#!/usr/bin/env bash

########################################
# hyprx clean
########################################
#
# Deliberately conservative: only removes
# things that either regenerate themselves
# automatically (package cache, thumbnail/
# shader caches) or are explicitly time-
# boxed (screenshots older than 2 days).
# Never touches user data or anything not
# owned by HyprX/the package manager.
#

DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

header
info_log "Running cleanup"

echo

########################################
# Package manager cache
########################################

section "Package cache"

if $DRY_RUN; then
    info "[dry-run] Would remove stale pacman cache download-* temp files"
    info "[dry-run] Would run the $PACKAGE_MANAGER cache clean"
else
    clean_package_cache
fi

echo

########################################
# Orphaned packages
########################################

section "Orphaned packages"

if $DRY_RUN; then

    mapfile -t orphans < <(list_orphan_packages)

    if ((${#orphans[@]})); then
        printf "%s\n" "${orphans[@]}"
        info "[dry-run] Would prompt to remove the above with: sudo pacman -Rns"
    else
        success "No orphan packages found."
    fi

else
    remove_orphan_packages
fi

echo

########################################
# Screenshots older than 2 days
########################################

section "Old screenshots"

SCREENSHOT_DIR="${HYPRX_TARGET_HOME:-$HOME}/Pictures/Screenshots"

if [[ -d "$SCREENSHOT_DIR" ]]; then

    mapfile -t old_shots < <(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -mtime +2)

    if ((${#old_shots[@]})); then

        if $DRY_RUN; then
            printf "%s\n" "${old_shots[@]}"
            info "[dry-run] Would delete ${#old_shots[@]} screenshot(s) older than 2 days"
        else
            rm -f "${old_shots[@]}"
            success "Removed ${#old_shots[@]} screenshot(s) older than 2 days."
        fi

    else
        success "No screenshots older than 2 days."
    fi

else
    info "No screenshots directory found."
fi

echo

########################################
# Regenerable caches
########################################
#
# Every entry here regenerates itself
# automatically the next time it's needed -
# safe to clear unconditionally.
#

section "Regenerable caches"

CACHE_TARGETS=(
    "${HYPRX_TARGET_HOME:-$HOME}/.cache/thumbnails"
    "${HYPRX_TARGET_HOME:-$HOME}/.cache/mesa_shader_cache"
)

for dir in "${CACHE_TARGETS[@]}"; do

    [[ -d "$dir" ]] || continue

    if $DRY_RUN; then
        info "[dry-run] Would clear: $dir"
    else
        find "$dir" -mindepth 1 -delete 2>/dev/null
        success "Cleared $dir"
    fi

done

echo

divider

if $DRY_RUN; then
    info "Dry run complete - nothing was removed."
else
    success "Cleanup completed."
    success_log "Cleanup completed successfully."
fi