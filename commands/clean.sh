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

########################################
# System journal (absorbed from the old
# scripts/system-clean.sh, now removed -
# see git history)
########################################
#
# Time-boxed, same philosophy as the
# screenshot cleanup above: only entries
# older than the retention window are
# ever touched, so this never needs a
# confirmation prompt.
#

section "System Logs"

JOURNAL_RETENTION_DAYS=7

if $DRY_RUN; then
    info "[dry-run] Would vacuum journal entries older than ${JOURNAL_RETENTION_DAYS} days"
else
    if command -v sudo >/dev/null 2>&1 && command -v journalctl >/dev/null 2>&1; then
        sudo journalctl --vacuum-time="${JOURNAL_RETENTION_DAYS}d"
        success "Vacuumed journal entries older than ${JOURNAL_RETENTION_DAYS} days"
    else
        info "journalctl/sudo not available - skipping"
    fi
fi

echo

########################################
# Temporary files
########################################
#
# Age-gated (not a blanket wipe like the
# old system-clean.sh) so this can't touch
# a socket/lockfile a running process on
# this session dropped in /tmp minutes ago.
# Note the age filter applies per top-level
# entry, not recursively - a dir older than
# the threshold is removed whole even if a
# file inside it is newer.
#

section "Temporary Files"

TMP_AGE_DAYS=1
CURRENT_USER="$(id -un)"

if [[ -d /tmp ]]; then

    mapfile -t old_tmp < <(find /tmp -mindepth 1 -user "$CURRENT_USER" -mtime "+$TMP_AGE_DAYS" 2>/dev/null)

    if ((${#old_tmp[@]})); then
        if $DRY_RUN; then
            printf "%s\n" "${old_tmp[@]}"
            info "[dry-run] Would delete ${#old_tmp[@]} item(s) in /tmp older than ${TMP_AGE_DAYS} day(s), owned by $CURRENT_USER"
        else
            rm -rf "${old_tmp[@]}" 2>/dev/null
            success "Removed ${#old_tmp[@]} item(s) in /tmp older than ${TMP_AGE_DAYS} day(s)"
        fi
    else
        success "No stale temp files owned by $CURRENT_USER."
    fi

fi

echo

divider

if $DRY_RUN; then
    info "Dry run complete - nothing was removed."
else
    success "Cleanup completed."
    success_log "Cleanup completed successfully."
fi