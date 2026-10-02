#!/usr/bin/env bash

# hyprx clean [--dry-run]
#
# Conservative: removes only what regenerates itself or is explicitly
# time-boxed (screenshots over 2 days old). Never touches user data.
#
#   --dry-run / HYPRX_DRY_RUN=1   report everything, remove nothing
#   HYPRX_CLEAN_ROOT=<dir>         aim the home-relative paths at <dir> and
#                                  report the steps that cannot be redirected
#                                  - this is how the suite tests real deletions

DRY_RUN=false
FAILURES=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            hyprx_ui_section "hyprx clean"
            cat <<'EOF'
Usage:
    hyprx clean [--dry-run]

Options:
    --dry-run   Report every step without removing anything.

Environment:
    HYPRX_CLEAN_ROOT   Redirect the home-relative cleanup targets
                       (screenshots, ~/.cache) at this directory.
                       System-wide steps are then reported, not performed.
    HYPRX_DRY_RUN=1    Same as --dry-run.
EOF
            exit 0
            ;;
        *)
            hyprx_ui_error "Unknown option: $arg"
            hyprx_ui_info "Run 'hyprx clean --help' for usage."
            exit 1
            ;;
    esac
done

[[ "${HYPRX_DRY_RUN:-0}" == "1" ]] && DRY_RUN=true

CLEAN_ROOT="${HYPRX_CLEAN_ROOT:-${HYPRX_TARGET_HOME:-$HOME}}"
SANDBOX=false
[[ -n "${HYPRX_CLEAN_ROOT:-}" ]] && SANDBOX=true

# Steps outside CLEAN_ROOT cannot be sandboxed, so they are reported, not performed.
REPORT_ONLY=false
$DRY_RUN && REPORT_ONLY=true
$SANDBOX && REPORT_ONLY=true

# Escalate only if sudo works without a password prompt; otherwise say so
# rather than dying or silently doing nothing.
CLEAN_CAN_SUDO=false
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    CLEAN_CAN_SUDO=true
fi

hyprx_ui_header
hyprx_logger_info "Running cleanup"

if $SANDBOX; then
    hyprx_ui_warn "SANDBOX - home-relative targets redirected to $CLEAN_ROOT;"
    hyprx_ui_warn "system-wide steps (package cache, orphans, journal, /tmp) will be reported, not performed."
    echo
fi

echo

# Package manager cache

hyprx_ui_section "Package cache"

if $REPORT_ONLY; then
    hyprx_util_would "remove stale pacman cache download-* temp files"
    hyprx_util_would "run the $HYPRX_DETECT_PACKAGE_MANAGER cache clean"
elif ! $CLEAN_CAN_SUDO; then
    hyprx_ui_warn "sudo unavailable or unauthenticated - skipping package cache clean"
    FAILURES=$((FAILURES + 1))
else
    hyprx_pkg_clean_cache || FAILURES=$((FAILURES + 1))
fi

echo

# Orphaned packages

hyprx_ui_section "Orphaned packages"

mapfile -t ORPHANS < <(hyprx_pkg_list_orphans)

if ((${#ORPHANS[@]} == 0)); then
    hyprx_ui_success "No orphan packages found."
elif $REPORT_ONLY; then
    printf "%s\n" "${ORPHANS[@]}"
    hyprx_util_would "prompt to remove the above with: sudo pacman -Rns"
elif ! $CLEAN_CAN_SUDO; then
    hyprx_ui_warn "sudo unavailable or unauthenticated - leaving ${#ORPHANS[@]} orphan(s) installed"
    FAILURES=$((FAILURES + 1))
else
    hyprx_pkg_remove_orphans || FAILURES=$((FAILURES + 1))
fi

echo

# Screenshots older than 2 days
# Redirectable: runs for real under a sandbox, which is the point.

hyprx_ui_section "Old screenshots"

SCREENSHOT_DIR="$CLEAN_ROOT/Pictures/Screenshots"
SCREENSHOT_AGE_DAYS=2

if [[ -d "$SCREENSHOT_DIR" ]]; then

    mapfile -t OLD_SHOTS < <(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -mtime "+$SCREENSHOT_AGE_DAYS")

    if ((${#OLD_SHOTS[@]})); then

        if $DRY_RUN; then
            printf "%s\n" "${OLD_SHOTS[@]}"
            hyprx_util_would "delete ${#OLD_SHOTS[@]} screenshot(s) older than $SCREENSHOT_AGE_DAYS days"
        else
            rm -f "${OLD_SHOTS[@]}"
            hyprx_ui_success "Removed ${#OLD_SHOTS[@]} screenshot(s) older than $SCREENSHOT_AGE_DAYS days."
        fi

    else
        hyprx_ui_success "No screenshots older than $SCREENSHOT_AGE_DAYS days."
    fi

else
    hyprx_ui_info "No screenshots directory found ($SCREENSHOT_DIR)."
fi

echo

# Regenerable caches
# Redirectable: runs for real under a sandbox.

hyprx_ui_section "Regenerable caches"

CACHE_TARGETS=(
    "$CLEAN_ROOT/.cache/thumbnails"
    "$CLEAN_ROOT/.cache/mesa_shader_cache"
)

CACHES_CLEARED=0

for dir in "${CACHE_TARGETS[@]}"; do

    [[ -d "$dir" ]] || continue

    CACHES_CLEARED=$((CACHES_CLEARED + 1))

    if $DRY_RUN; then
        hyprx_util_would "clear: $dir"
    else
        find "$dir" -mindepth 1 -delete 2>/dev/null
        hyprx_ui_success "Cleared $dir"
    fi

done

(( CACHES_CLEARED == 0 )) && hyprx_ui_info "No regenerable caches present."

echo

# System journal
# System-wide: report only under --dry-run or a sandbox.

hyprx_ui_section "System Logs"

JOURNAL_RETENTION_DAYS=7

if $REPORT_ONLY; then
    hyprx_util_would "vacuum journal entries older than $JOURNAL_RETENTION_DAYS days"
elif ! command -v journalctl >/dev/null 2>&1; then
    hyprx_ui_info "journalctl not available - skipping"
elif ! $CLEAN_CAN_SUDO; then
    hyprx_ui_warn "sudo unavailable or unauthenticated - skipping journal vacuum"
    FAILURES=$((FAILURES + 1))
else
    sudo journalctl --vacuum-time="${JOURNAL_RETENTION_DAYS}d"
    hyprx_ui_success "Vacuumed journal entries older than $JOURNAL_RETENTION_DAYS days"
fi

echo

# Temporary files
# System-wide: report only under --dry-run or a sandbox.

hyprx_ui_section "Temporary Files"

TMP_AGE_DAYS=1
CURRENT_USER="$(id -un)"

if $REPORT_ONLY; then
    mapfile -t OLD_TMP < <(find /tmp -mindepth 1 -user "$CURRENT_USER" -mtime "+$TMP_AGE_DAYS" 2>/dev/null)
    if ((${#OLD_TMP[@]})); then
        hyprx_util_would "delete ${#OLD_TMP[@]} item(s) in /tmp older than $TMP_AGE_DAYS day(s), owned by $CURRENT_USER"
    else
        hyprx_ui_info "No stale temp files owned by $CURRENT_USER."
    fi
elif [[ -d /tmp ]]; then

    mapfile -t OLD_TMP < <(find /tmp -mindepth 1 -user "$CURRENT_USER" -mtime "+$TMP_AGE_DAYS" 2>/dev/null)

    if ((${#OLD_TMP[@]})); then
        rm -rf "${OLD_TMP[@]}" 2>/dev/null
        hyprx_ui_success "Removed ${#OLD_TMP[@]} item(s) in /tmp older than $TMP_AGE_DAYS day(s)"
    else
        hyprx_ui_success "No stale temp files owned by $CURRENT_USER."
    fi

fi

echo

hyprx_ui_divider

if $REPORT_ONLY; then
    if $SANDBOX; then
        hyprx_ui_info "Sandbox run complete - see above for what was and was not touched."
    else
        hyprx_ui_info "Dry run complete - nothing was removed."
    fi
elif (( FAILURES > 0 )); then
    hyprx_ui_warn "Cleanup finished with $FAILURES step(s) skipped or failed - see above."
    hyprx_logger_warn "Cleanup finished with $FAILURES skipped/failed step(s)"
    exit 1
else
    hyprx_ui_success "Cleanup completed."
    hyprx_logger_success "Cleanup completed successfully."
fi

exit 0
