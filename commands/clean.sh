#!/usr/bin/env bash

# hyprx clean [--dry-run] [--deep] [--yes]
#
# Conservative by default: removes only what regenerates itself or is
# explicitly time-boxed (screenshots over N days old). Never touches user data
# unless --deep is given, and even then never a browser profile.
#
#   --dry-run / HYPRX_DRY_RUN=1   report everything, remove nothing
#   --deep                        also clear the large regenerable caches,
#                                 empty the trash, and drop coredumps
#   --yes                         do not prompt
#   HYPRX_CLEAN_ROOT=<dir>        aim the home-relative paths at <dir> and
#                                 report the steps that cannot be redirected
#                                 - this is how the suite tests real deletions
#
# Every step reports the bytes it actually reclaimed, so a run that freed
# nothing says so instead of claiming success.

DRY_RUN=false
DEEP=false
ASSUME_YES=false
FAILURES=0
FREED=0
# Steps that were skipped because root was unavailable. Counted separately from
# FAILURES so a non-interactive `hyprx clean` does not exit 1 for a successful
# cleanup - see README.md "Steps needing sudo are skipped with a message".
SKIPPED=0

SCREENSHOT_AGE_DAYS="${SCREENSHOT_AGE_DAYS:-2}"
TMP_AGE_DAYS="${TMP_AGE_DAYS:-1}"
JOURNAL_RETENTION_DAYS="${JOURNAL_RETENTION_DAYS:-7}"
SNAPSHOT_KEEP="${SNAPSHOT_KEEP:-5}"
REPORT_KEEP="${REPORT_KEEP:-10}"
LOG_KEEP="${LOG_KEEP:-3}"

usage() {
    cat <<'EOF'
Usage:
    hyprx clean [--dry-run] [--deep] [--yes]

Options:
    --dry-run   Report every step and the bytes it would free. Removes nothing.
    --deep      Also clear the large regenerable caches (AUR build cache,
                nvidia shaders, fontconfig, pip), empty the trash, and delete
                coredumps. Off by default because the trash is recoverable data.
    --yes       Do not prompt before removing orphaned packages.

Environment:
    HYPRX_CLEAN_ROOT   Redirect the home-relative cleanup targets at this
                       directory. System-wide steps are reported, not performed.
    HYPRX_DRY_RUN=1    Same as --dry-run.
    SCREENSHOT_AGE_DAYS  Age at which a screenshot is removed. Default 2.
    TMP_AGE_DAYS         Age at which stale files in /tmp/$USER are removed.
                        Default 1. Scoped to your own per-user directory and to
                        its top level, so a live socket in a directory that
                        happens to be old is never removed.
    JOURNAL_RETENTION_DAYS  Journal entries kept. Default 7.
    SNAPSHOT_KEEP       Rollback snapshots to keep. Default 5.
    REPORT_KEEP         hyprx doctor reports to keep. Default 10.
    LOG_KEEP            Rotated log generations to keep. Default 3.
                       Also exported as HYPRX_LOG_KEEP, which is what
                       lib/logger.sh reads - the two were unrelated numbers
                       before, so this step could never fire.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --deep)    DEEP=true ;;
        --yes|-y)  ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;;
        *)
            hyprx_ui_error "Unknown option: $arg"
            usage
            exit 1
            ;;
    esac
done

[[ "${HYPRX_DRY_RUN:-0}" == "1" ]] && DRY_RUN=true

CLEAN_ROOT="${HYPRX_CLEAN_ROOT:-${HYPRX_TARGET_HOME:-$HOME}}"
SANDBOX=false
[[ -n "${HYPRX_CLEAN_ROOT:-}" ]] && SANDBOX=true

# Dry run removes nothing at all. Sandbox removes the CLEAN_ROOT-relative items
# for real - the test suite needs real deletions - but cannot redirect anything
# outside CLEAN_ROOT, so those steps are reported instead. Conflating the two
# made a sandboxed run claim it had removed nothing.
SKIP_SYSTEM=false
$DRY_RUN && SKIP_SYSTEM=true
$SANDBOX && SKIP_SYSTEM=true

if $DRY_RUN; then
    HYPRX_REPORT_PREFIX="dry-run"
elif $SANDBOX; then
    HYPRX_REPORT_PREFIX="sandboxed"
fi

CLEAN_CAN_SUDO=false
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    CLEAN_CAN_SUDO=true
fi

# Clean prunes snapshots and state alongside caches, so it is a writer like
# install and rollback - same global lock, released by the EXIT trap.
hyprx_lock_acquire || exit 3

# The step add_freed reports under. Set before each section so the event
# stream carries per-step bytes for the Phase-2 reclaimed-bytes visual.
HYPRX_CLEAN_STEP=""

# Terminal event for the run. clean.sh exits from several places (sandbox
# short-circuit, failure tally, success), so one EXIT-scoped emit covers
# them all instead of one call per exit. Registered on the dispatcher's hook
# chain rather than a trap of its own, which would replace the dispatcher's
# trap and strand the sudo refresher and lock.
# shellcheck disable=SC2329  # invoked via the EXIT hook chain, not by name
hyprx_clean_finish() {
    (( BASH_SUBSHELL == 0 )) || return 0
    hyprx_event clean.completed bytes="$FREED" skipped="$SKIPPED" failures="$FAILURES"
}
hyprx_on_exit hyprx_clean_finish

# Bytes a path occupies right now, empty if absent.
size_of() {
    hyprx_state_size "$1"
}

# Accumulate into the run total. Deliberately prints nothing: the caller
# formats its own line, so this must not emit a second size token. The event
# carries the per-step bytes HYPRX_CLEAN_STEP names (see above).
add_freed() {
    local bytes="${1:-0}"
    (( bytes > 0 )) && FREED=$((FREED + bytes))
    hyprx_event clean.step step="$HYPRX_CLEAN_STEP" bytes="$bytes"
    return 0
}

# "(2.6M)" or "" for zero, for appending to a success line.
freed_note() {
    local bytes="${1:-0}"
    (( bytes > 0 )) && printf ' (%s)' "$(hyprx_state_human "$bytes")"
    return 0
}

# A cache dir cleared for real, or reported under dry-run.
clear_cache_dir() {
    local dir="$1" label="${2:-$1}" before after

    [[ -d "$dir" ]] || return 0

    before="$(size_of "$dir")"
    [[ -z "$before" ]] && before=0

    if $DRY_RUN; then
        hyprx_util_would "clear $label - frees $(hyprx_state_human "$before")"
        add_freed "$before"
        return 0
    fi

    find "$dir" -mindepth 1 -delete 2>/dev/null
    after="$(size_of "$dir")"
    [[ -z "$after" ]] && after=0

    local delta=$((before - after))
    add_freed "$delta"
    hyprx_ui_success "Cleared $label$(freed_note "$delta")"
}

hyprx_ui_header
hyprx_logger_info "Running cleanup"

if $SANDBOX; then
    hyprx_ui_warn "SANDBOX - home-relative targets redirected to $CLEAN_ROOT."
    hyprx_ui_warn "System-wide steps will be reported, not performed."
    echo
fi

echo

########################################
# Package manager cache
########################################

HYPRX_CLEAN_STEP="Package cache"
hyprx_ui_section "Package cache"

if $SKIP_SYSTEM; then
    before="$(size_of /var/cache/pacman/pkg)"
    hyprx_util_would "remove stale pacman cache download-* temp files"
    # An upper bound on what the clean could reclaim, not a measured saving, so
    # it is deliberately kept out of the run total.
    hyprx_util_would "run the $HYPRX_DETECT_PACKAGE_MANAGER cache clean - could free up to $(hyprx_state_human "${before:-0}")"
elif ! $CLEAN_CAN_SUDO; then
    # A SKIP, not a failure. README.md:109-110 promises "Steps needing sudo are
    # skipped with a message when no cached sudo ticket exists. The run still
    # completes and still reports what it did free." Counting this as a failure
    # made `hyprx clean` exit 1 on a perfectly normal non-interactive run, so
    # scripts and CI saw a failing command for a successful cleanup.
    hyprx_ui_warn "sudo unavailable or unauthenticated - skipping package cache clean"
    SKIPPED=$((SKIPPED + 1))
else
    hyprx_pkg_clean_cache || FAILURES=$((FAILURES + 1))
fi

echo

########################################
# Orphaned packages
########################################

HYPRX_CLEAN_STEP="Orphaned packages"
hyprx_ui_section "Orphaned packages"

mapfile -t ORPHANS < <(hyprx_pkg_list_orphans)

if ((${#ORPHANS[@]} == 0)); then
    hyprx_ui_success "No orphan packages found."
elif $SKIP_SYSTEM; then
    printf "%s\n" "${ORPHANS[@]}"
    hyprx_util_would "remove ${#ORPHANS[@]} orphan package(s) with: sudo pacman -Rns"
elif ! $CLEAN_CAN_SUDO; then
    hyprx_ui_warn "sudo unavailable or unauthenticated - leaving ${#ORPHANS[@]} orphan(s) installed"
    SKIPPED=$((SKIPPED + 1))
elif $ASSUME_YES; then
    sudo pacman -Rns --noconfirm "${ORPHANS[@]}"
    hyprx_ui_success "Removed ${#ORPHANS[@]} orphan package(s)."
else
    hyprx_pkg_remove_orphans || FAILURES=$((FAILURES + 1))
fi

echo

########################################
# Screenshots older than N days
########################################

HYPRX_CLEAN_STEP="Old screenshots"
hyprx_ui_section "Old screenshots"

SCREENSHOT_DIR="$CLEAN_ROOT/Pictures/Screenshots"

if [[ -d "$SCREENSHOT_DIR" ]]; then
    mapfile -t OLD_SHOTS < <(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -mtime "+$SCREENSHOT_AGE_DAYS")

    if ((${#OLD_SHOTS[@]})); then
        before=0
        for f in "${OLD_SHOTS[@]}"; do
            s="$(size_of "$f")"; before=$((before + ${s:-0}))
        done

        if $DRY_RUN; then
            printf "%s\n" "${OLD_SHOTS[@]}"
            hyprx_util_would "delete ${#OLD_SHOTS[@]} screenshot(s) older than $SCREENSHOT_AGE_DAYS days - frees $(hyprx_state_human "$before")"
            add_freed "$before"
        else
            rm -f "${OLD_SHOTS[@]}"
            add_freed "$before"
            hyprx_ui_success "Removed ${#OLD_SHOTS[@]} screenshot(s) older than $SCREENSHOT_AGE_DAYS days.$(freed_note "$before")"
        fi
    else
        hyprx_ui_success "No screenshots older than $SCREENSHOT_AGE_DAYS days."
    fi
else
    hyprx_ui_info "No screenshots directory found ($SCREENSHOT_DIR)."
fi

echo

########################################
# Regenerable caches
########################################

HYPRX_CLEAN_STEP="Regenerable caches"
hyprx_ui_section "Regenerable caches"

CACHES_CLEARED=0
for dir in \
    "$CLEAN_ROOT/.cache/thumbnails" \
    "$CLEAN_ROOT/.cache/mesa_shader_cache"
do
    [[ -d "$dir" ]] || continue
    CACHES_CLEARED=$((CACHES_CLEARED + 1))
    clear_cache_dir "$dir"
done

(( CACHES_CLEARED == 0 )) && hyprx_ui_info "No regenerable caches present."

echo

########################################
# Large caches - --deep only
########################################

if $DEEP; then

    HYPRX_CLEAN_STEP="Large caches (--deep)"
    hyprx_ui_section "Large caches (--deep)"

    # All fully regenerable. The browser profile is deliberately excluded: it is
    # regenerable but costs a long re-download and a cold start.
    for dir in \
        "$CLEAN_ROOT/.cache/yay" \
        "$CLEAN_ROOT/.cache/paru" \
        "$CLEAN_ROOT/.cache/nvidia" \
        "$CLEAN_ROOT/.cache/fontconfig" \
        "$CLEAN_ROOT/.cache/pip"
    do
        [[ -d "$dir" ]] || continue
        clear_cache_dir "$dir" "${dir#"$CLEAN_ROOT"/}"
    done

    echo

    ########################################
    # Trash
    ########################################

    HYPRX_CLEAN_STEP="Trash"
    hyprx_ui_section "Trash"

    TRASH_DIR="$CLEAN_ROOT/.local/share/Trash"
    TRASH_SIZE="$(size_of "$TRASH_DIR")"

    if [[ -z "$TRASH_SIZE" || "$TRASH_SIZE" == 0 ]]; then
        hyprx_ui_success "Trash is already empty."
    elif $SKIP_SYSTEM; then
        hyprx_util_would "empty the trash - frees $(hyprx_state_human "$TRASH_SIZE") (recoverable data, so --deep only)"
        add_freed "$TRASH_SIZE"
    elif ! command -v gio >/dev/null 2>&1; then
        hyprx_ui_warn "gio not available - cannot empty the trash non-destructively"
    else
        # Measure, do not assume. This step used to add the full pre-trash size
        # to the run total and print success unconditionally, so a failed
        # `gio trash --empty` was reported as bytes reclaimed. That directly
        # contradicts this command's own claim (README.md:90) that every step
        # reports what it actually reclaimed, and it was the only step in this
        # file that skipped the before/after measurement.
        gio trash --empty >/dev/null 2>&1
        TRASH_AFTER="$(size_of "$TRASH_DIR")"
        [[ -z "$TRASH_AFTER" ]] && TRASH_AFTER=0
        trash_delta=$(( ${TRASH_SIZE:-0} - TRASH_AFTER ))

        if (( trash_delta > 0 )); then
            add_freed "$trash_delta"
            hyprx_ui_success "Emptied the trash.$(freed_note "$trash_delta")"
        elif (( ${TRASH_AFTER:-0} > 0 )); then
            # Still not empty: gio either failed or a new file landed mid-run.
            hyprx_ui_warn "Trash not empty ($(hyprx_state_human "$TRASH_AFTER") remaining) - nothing counted"
            FAILURES=$((FAILURES + 1))
        else
            hyprx_ui_success "Trash was already empty."
        fi
    fi

    echo

    ########################################
    # Coredumps
    ########################################

    HYPRX_CLEAN_STEP="Coredumps"
    hyprx_ui_section "Coredumps"

    # Grouped by program, because "5x hyprpaper" tells you something a list of
    # PIDs does not. Column 10 is the executable. The per-dump size column
    # carries a unit suffix ("10.4M") so it cannot be summed - the total is
    # taken from the coredump directory instead.
    coredump_summary() {
        coredumpctl list --no-pager 2>/dev/null | tail -n +2 \
            | awk 'NF >= 10 { name = $10; sub(/^.*\//, "", name); count[name]++ }
                   END { for (n in count) printf "%s|%d\n", n, count[n] }' \
            | sort
    }

    if ! command -v coredumpctl >/dev/null 2>&1; then
        hyprx_ui_info "coredumpctl not available - skipping"
    elif $SKIP_SYSTEM; then
        summary="$(coredump_summary)"
        if [[ -n "$summary" ]]; then
            n="$(printf '%s\n' "$summary" | awk -F'|' '{t += $2} END {print t + 0}')"
            hyprx_util_would "delete $n coredump(s)"
            printf '%s\n' "$summary" | while IFS='|' read -r name count; do
                printf '      %s x%s\n' "$name" "$count"
            done
        else
            hyprx_ui_success "No coredumps."
        fi
    elif ! $CLEAN_CAN_SUDO; then
        hyprx_ui_warn "sudo unavailable or unauthenticated - skipping coredump removal"
        SKIPPED=$((SKIPPED + 1))
    else
        summary="$(coredump_summary)"
        if [[ -n "$summary" ]]; then
            n="$(printf '%s\n' "$summary" | awk -F'|' '{t += $2} END {print t + 0}')"
            printf '%s\n' "$summary" | while IFS='|' read -r name count; do
                printf '      dropping %s x%s\n' "$name" "$count"
            done
            before="$(size_of /var/lib/systemd/coredump)"
            sudo coredumpctl delete >/dev/null 2>&1
            after="$(size_of /var/lib/systemd/coredump)"
            d=$(( ${before:-0} - ${after:-0} ))
            add_freed "$d"
            hyprx_ui_success "Deleted $n coredump(s).$(freed_note "$d")"
        else
            hyprx_ui_success "No coredumps."
        fi
    fi

    echo

fi

########################################
# System journal
########################################

HYPRX_CLEAN_STEP="System Logs"
hyprx_ui_section "System Logs"

if $SKIP_SYSTEM; then
    hyprx_util_would "vacuum journal entries older than $JOURNAL_RETENTION_DAYS days"
elif ! command -v journalctl >/dev/null 2>&1; then
    hyprx_ui_info "journalctl not available - skipping"
elif ! $CLEAN_CAN_SUDO; then
    hyprx_ui_warn "sudo unavailable or unauthenticated - skipping journal vacuum"
    SKIPPED=$((SKIPPED + 1))
else
    sudo journalctl --vacuum-time="${JOURNAL_RETENTION_DAYS}d"
    hyprx_ui_success "Vacuumed journal entries older than $JOURNAL_RETENTION_DAYS days"
fi

echo

########################################
# Temporary files
########################################

HYPRX_CLEAN_STEP="Temporary Files"
hyprx_ui_section "Temporary Files"

CURRENT_USER="$(id -un)"

if $SKIP_SYSTEM; then
    mapfile -t OLD_TMP < <(find "/tmp/$CURRENT_USER" -mindepth 1 -maxdepth 1 -mtime "+$TMP_AGE_DAYS" 2>/dev/null)
    if ((${#OLD_TMP[@]})); then
        hyprx_util_would "delete ${#OLD_TMP[@]} item(s) from /tmp/$CURRENT_USER older than $TMP_AGE_DAYS day(s)"
    else
        hyprx_ui_info "No stale files in /tmp/$CURRENT_USER."
    fi
elif [[ -d /tmp ]]; then
    # Scoped to /tmp/$CURRENT_USER and to the top level only.
    #
    # This used to walk ALL of /tmp for anything owned by the user and `rm -rf`
    # it, which meant deleting the contents of directories it had not inspected:
    # -mtime on a directory reports the directory's own mtime, so a day-old
    # directory holding a live socket was removed along with everything in it.
    # systemd already maintains /tmp/$USER for exactly this purpose, so the
    # conventional location is both safer and where users expect it.
    USER_TMP="/tmp/$CURRENT_USER"

    if [[ ! -d "$USER_TMP" ]]; then
        hyprx_ui_success "No per-user temp directory ($USER_TMP)."
    else
        mapfile -t OLD_TMP < <(find "$USER_TMP" -mindepth 1 -maxdepth 1 -mtime "+$TMP_AGE_DAYS" 2>/dev/null)
        if ((${#OLD_TMP[@]})); then
            tmp_bytes=0
            for t in "${OLD_TMP[@]}"; do
                s="$(size_of "$t")"
                tmp_bytes=$((tmp_bytes + ${s:-0}))
            done

            if $DRY_RUN; then
                hyprx_util_would "remove ${#OLD_TMP[@]} item(s) from $USER_TMP older than $TMP_AGE_DAYS day(s) - frees $(hyprx_state_human "$tmp_bytes")"
                add_freed "$tmp_bytes"
            else
                rm -rf -- "${OLD_TMP[@]}" 2>/dev/null
                add_freed "$tmp_bytes"
                hyprx_ui_success "Removed ${#OLD_TMP[@]} item(s) from $USER_TMP older than $TMP_AGE_DAYS day(s).$(freed_note "$tmp_bytes")"
            fi
        else
            hyprx_ui_success "No stale files in $USER_TMP older than $TMP_AGE_DAYS day(s)."
        fi
    fi
fi

echo

########################################
# HyprX's own state
########################################

HYPRX_CLEAN_STEP="HyprX state"
hyprx_ui_section "HyprX state"

STATE_DIR="${HYPRX_STATE_DIR:-$HOME/.local/state/hyprx}"

# Old snapshots. Their config-backups go with them - a snapshot whose backup
# dir is deleted can no longer restore anything, so keeping it is pointless.
if [[ -d "$HYPRX_STATE_SNAPSHOT_DIR" ]]; then
    mapfile -t OLD_SNAPS < <(find "$HYPRX_STATE_SNAPSHOT_DIR" -maxdepth 1 -name '*.snapshot' -printf '%f\n' | sort | head -n "-$SNAPSHOT_KEEP")
    if ((${#OLD_SNAPS[@]})); then
        for s in "${OLD_SNAPS[@]}"; do
            id="${s%.snapshot}"
            b="$(size_of "$(hyprx_snapshot_backup_dir_for "$id")")"

            extra=""
            [[ -n "$b" ]] && extra=" + its config backup ($(hyprx_state_human "$b"))"

            if $DRY_RUN; then
                hyprx_util_would "drop snapshot $id$extra"
            else
                hyprx_snapshot_remove "$id"
                hyprx_ui_info "Dropped snapshot $id (kept last $SNAPSHOT_KEEP)"
            fi
        done
    else
        hyprx_ui_success "No snapshots beyond the last $SNAPSHOT_KEEP."
    fi
else
    hyprx_ui_info "No snapshot directory."
fi

# Orphaned config backups - a snapshot id that no longer has a .snapshot file
# can never be rolled back to.
if [[ -d "$HYPRX_STATE_BACKUP_DIR" ]]; then
    mapfile -t STALE_BACKUPS < <(
        for d in "$HYPRX_STATE_BACKUP_DIR"/*/; do
            [[ -d "$d" ]] || continue
            [[ -f "$HYPRX_STATE_SNAPSHOT_DIR/$(basename "$d").snapshot" ]] || basename "$d"
        done
    )
    if ((${#STALE_BACKUPS[@]})); then
        for id in "${STALE_BACKUPS[@]}"; do
            b="$(size_of "$HYPRX_STATE_BACKUP_DIR/$id")"
            if $DRY_RUN; then
                hyprx_util_would "drop orphaned config backup $id - frees $(hyprx_state_human "${b:-0}")"
                add_freed "${b:-0}"
            else
                rm -rf "${HYPRX_STATE_BACKUP_DIR:?}/$id"
                add_freed "${b:-0}"
                hyprx_ui_info "Dropped orphaned config backup $id.$(freed_note "${b:-0}")"
            fi
        done
    else
        hyprx_ui_success "No orphaned config backups."
    fi
fi

# Old doctor reports.
if [[ -d "$HYPRX_STATE_REPORT_DIR" ]]; then
    mapfile -t OLD_REPORTS < <(find "$HYPRX_STATE_REPORT_DIR" -maxdepth 1 -name 'doctor-*.log' -printf '%f\n' | sort | head -n "-$REPORT_KEEP")
    if ((${#OLD_REPORTS[@]})); then
        for r in "${OLD_REPORTS[@]}"; do
            b="$(size_of "$HYPRX_STATE_REPORT_DIR/$r")"
            if $DRY_RUN; then
                hyprx_util_would "drop old report $r - frees $(hyprx_state_human "${b:-0}")"
                add_freed "${b:-0}"
            else
                rm -f "$HYPRX_STATE_REPORT_DIR/$r"
                add_freed "${b:-0}"
                hyprx_ui_info "Dropped old report $r.$(freed_note "${b:-0}")"
            fi
        done
        (( DRY_RUN )) || hyprx_ui_info "Kept the last $REPORT_KEEP doctor reports."
    else
        hyprx_ui_success "No reports beyond the last $REPORT_KEEP."
    fi
fi

# Rotated log generations past the keep count.
#
# HYPRX_LOG_KEEP (lib/logger.sh) is the variable the logger actually reads.
# This used to read a bare LOG_KEEP, defaulted to 3, and never wrote it back to
# HYPRX_LOG_KEEP - so the two were unrelated numbers, the logger only ever
# produced .1, and this loop could never fire. One variable, set in both places.
#
# The user-facing name stays LOG_KEEP because that is what `clean --help`
# documents; it is translated once, here.
if [[ -n "${HYPRX_LOG_KEEP_SET:-}" ]]; then
    LOG_KEEP="$HYPRX_LOG_KEEP_SET"
fi
export HYPRX_LOG_KEEP="$LOG_KEEP"

for f in "$HYPRX_LOGGER_FILE".*; do
    [[ -f "$f" ]] || continue
    gen="${f##*.}"
    if [[ "$gen" =~ ^[0-9]+$ ]] && (( gen > LOG_KEEP )); then
        b="$(size_of "$f")"
        if $DRY_RUN; then
            hyprx_util_would "drop rotated log $f - frees $(hyprx_state_human "${b:-0}")"
            add_freed "${b:-0}"
        else
            rm -f "$f"
            add_freed "${b:-0}"
            hyprx_ui_info "Dropped rotated log generation $gen (kept $LOG_KEEP).$(freed_note "${b:-0}")"
        fi
    fi
done

echo

########################################
# Summary
########################################

hyprx_ui_divider

if $DRY_RUN; then
    hyprx_ui_info "Dry run complete. Nothing was removed."
    hyprx_ui_info "Would free approximately $(hyprx_state_human "$FREED")."
    $DEEP || hyprx_ui_info "Add --deep to also clear large caches, the trash, and coredumps."
    exit 0
fi

if $SANDBOX; then
    # The CLEAN_ROOT-relative steps did run; the system-wide ones were reported.
    if (( FREED > 0 )); then
        hyprx_ui_success "Sandboxed cleanup removed $(hyprx_state_human "$FREED") from $CLEAN_ROOT."
    else
        hyprx_ui_success "Sandboxed cleanup removed nothing."
    fi
    hyprx_ui_info "System-wide steps were reported above, not performed."
    exit 0
fi

if (( FAILURES > 0 )); then
    hyprx_ui_warn "Cleanup finished with $FAILURES step(s) skipped or failed. Freed $(hyprx_state_human "$FREED")."
    hyprx_logger_warn "Cleanup finished with $FAILURES skipped/failed step(s)"
    exit 1
fi

if (( SKIPPED > 0 )); then
    hyprx_ui_info "$SKIPPED step(s) skipped (they need root). Not a failure."
fi

if (( FREED > 0 )); then
    hyprx_ui_success "Cleanup completed. Freed $(hyprx_state_human "$FREED")."
else
    hyprx_ui_success "Cleanup completed. Nothing needed removing."
fi
hyprx_logger_success "Cleanup completed. Freed $(hyprx_state_human "$FREED"), $SKIPPED skipped"

exit 0
