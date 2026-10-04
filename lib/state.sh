#!/usr/bin/env bash

# Single source of truth for every path HyprX writes to.
#
# Previously each consumer derived its own path, which meant doctor.sh ignored
# XDG_STATE_HOME while everything else honoured it, and eight separate
# expressions had to stay in agreement. Everything now resolves from
# HYPRX_STATE_DIR.
#
# Layout under the state dir:
#   hyprx.log                 operation log (rotated, see lib/logger.sh)
#   hyprx-install.log         per-package install failures
#   HyprX-Install-Report.txt  most recent install report
#   reports/                  timestamped hyprx doctor reports
#   snapshots/                rollback data
#   config-backups/           pre-deploy config copies, keyed by snapshot id
#   deployed-targets          which config dirs were last deployed
#   install.state             interrupted-install queue
#   last-wallpaper            last wallpaper wallpaper-restore.sh applied
#
# Transient caches deliberately do NOT live here - music metadata and similar
# stay under ~/.cache/hyprx where the XDG spec puts regenerable data.

HYPRX_STATE_DIR="${HYPRX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}"

# Back-compat: the log dir used to be the state dir and was settable on its own.
# Honour it if given so existing overrides and the test suite keep working.
if [[ -n "${HYPRX_LOGGER_DIR:-}" ]]; then
    HYPRX_STATE_DIR="$HYPRX_LOGGER_DIR"
fi
export HYPRX_STATE_DIR

# Every path is derived from HYPRX_STATE_DIR, and every override is named
# <DERIVED>_OVERRIDE rather than sharing a prefix with the thing it overrides.
#
# They used to be named HYPRX_STATE_SNAPSHOT_DIR (derived) and
# HYPRX_SNAPSHOT_DIR (override) - two names differing by one word, where the
# override silently wins. Reading either takes a second, and the second is
# usually the wrong one. The suffix makes the relationship visible at the call
# site, which is where it matters.
HYPRX_STATE_LOG_FILE="${HYPRX_LOG_FILE_OVERRIDE:-$HYPRX_STATE_DIR/hyprx.log}"
HYPRX_STATE_FAILURE_LOG="${HYPRX_FAILURE_LOG_OVERRIDE:-$HYPRX_STATE_DIR/hyprx-install.log}"
HYPRX_STATE_REPORT_FILE="${HYPRX_REPORT_FILE_OVERRIDE:-$HYPRX_STATE_DIR/HyprX-Install-Report.txt}"
HYPRX_STATE_REPORT_DIR="${HYPRX_REPORT_DIR_OVERRIDE:-$HYPRX_STATE_DIR/reports}"
HYPRX_STATE_SNAPSHOT_DIR="${HYPRX_SNAPSHOT_DIR_OVERRIDE:-$HYPRX_STATE_DIR/snapshots}"
HYPRX_STATE_BACKUP_DIR="${HYPRX_CONFIG_BACKUP_ROOT_OVERRIDE:-$HYPRX_STATE_DIR/config-backups}"
HYPRX_STATE_DEPLOYED_FILE="${HYPRX_DEPLOYED_TARGETS_FILE_OVERRIDE:-$HYPRX_STATE_DIR/deployed-targets}"
HYPRX_STATE_RECOVERY_DIR="${HYPRX_RECOVERY_STATE_DIR_OVERRIDE:-$HYPRX_STATE_DIR}"
HYPRX_STATE_WALLPAPER_FILE="${HYPRX_WALLPAPER_STATE_OVERRIDE:-$HYPRX_STATE_DIR/last-wallpaper}"

mkdir -p "$HYPRX_STATE_DIR" 2>/dev/null || true

# Total bytes under a path. Empty string if it does not exist.
hyprx_state_size() {
    [[ -e "$1" ]] || return 0
    du -sb "$1" 2>/dev/null | awk '{print $1}'
}

# Human readable, matching the units used elsewhere in the tool.
hyprx_state_human() {
    local bytes="${1:-0}"
    awk -v b="${bytes:-0}" 'BEGIN {
        if (b >= 1073741824) printf "%.1fG", b / 1073741824
        else if (b >= 1048576) printf "%.1fM", b / 1048576
        else if (b >= 1024)    printf "%.1fK", b / 1024
        else                   printf "%dB", b
    }'
}
