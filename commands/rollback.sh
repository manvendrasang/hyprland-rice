#!/usr/bin/env bash

ACTION="${1:-help}"

# Mutating actions funnel through here: one lock, one event bracket. The lock
# is released by the process EXIT trap (see lib/elevate.sh), so every return
# path below is covered without a release call at each site.
hyprx_rollback_run() {
    local id="$1"

    hyprx_lock_acquire || exit 3

    hyprx_event rollback.started id="$id"
    hyprx_snapshot_rollback "$id"
    local rc=$?
    hyprx_event rollback.completed id="$id" rc="$rc"
    return "$rc"
}

# Machine-readable twin of `rollback list` for the GUI snapshot browser.
# Counts AND names: the GUI shows counts in the list and names in the detail
# pane without a second round-trip.
hyprx_rollback_list_json() {
    local id date pkg_count cfg_count first=1
    printf '['
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        date="$(grep '^DATE=' "$HYPRX_SNAPSHOT_DIR_OVERRIDE/$id.snapshot" 2>/dev/null | cut -d= -f2-)"
        pkg_count="$(hyprx_snapshot_packages "$id" 2>/dev/null | grep -c . || true)"
        cfg_count="$(hyprx_snapshot_configs "$id" 2>/dev/null | grep -c . || true)"
        (( first == 0 )) && printf ','
        first=0
        printf '{"id":"%s","date":"%s","packages":%s,"configs":%s}' \
            "$(hyprx_event_escape "$id")" "$(hyprx_event_escape "$date")" \
            "$pkg_count" "$cfg_count"
    done < <(hyprx_snapshot_list_ids 2>/dev/null)
    printf ']\n'
}

case "$ACTION" in

    list)

        if [[ "${2:-}" == "--json" ]]; then
            hyprx_rollback_list_json
            exit 0
        fi

        hyprx_ui_section "Available Snapshots"

        if [[ -z "$(hyprx_snapshot_list)" ]]; then
            hyprx_ui_info "No snapshots found."
        else
            hyprx_snapshot_list
        fi

        ;;

    latest)

        SNAPSHOT_ID="$(hyprx_snapshot_latest)"

        [[ -z "$SNAPSHOT_ID" ]] && {
            hyprx_ui_info "No snapshots found."
            exit 0
        }

        hyprx_ui_section "Rolling back: $SNAPSHOT_ID"

        if hyprx_util_dry_run; then
            hyprx_ui_warn "Dry run - nothing was changed."
            hyprx_ui_info "Would roll back snapshot: $SNAPSHOT_ID"
            hyprx_snapshot_preview "$SNAPSHOT_ID"
            hyprx_event rollback.preview id="$SNAPSHOT_ID" \
                packages="$(hyprx_snapshot_packages "$SNAPSHOT_ID" 2>/dev/null | grep -c . || true)" \
                configs="$(hyprx_snapshot_configs "$SNAPSHOT_ID" 2>/dev/null | grep -c . || true)"
            exit 0
        fi

        if ! hyprx_util_confirm "Roll back $SNAPSHOT_ID? This removes packages and restores configs."; then
            hyprx_ui_info "Aborted."
            exit 0
        fi

        hyprx_rollback_run "$SNAPSHOT_ID"

        ;;

    "")

        hyprx_ui_section "Rollback"

        hyprx_ui_info "No snapshot specified. Use 'hyprx rollback list' to see options."

        ;;

    help)

        hyprx_ui_section "Rollback"

        cat <<EOF
Usage:
    hyprx rollback list [--json]  Show available snapshots
    hyprx rollback latest         Roll back the most recent install
    hyprx rollback <snapshot-id>  Roll back a specific snapshot

Options:
    --dry-run                     Report what would change, change nothing

Both rollback actions ask for confirmation before touching anything.

Notes:
    Only packages newly installed by HyprX in that run are removed.
    Packages that were already on your system before that install
    are never touched.
EOF
        ;;

    *)

        SNAPSHOT_ID="$ACTION"

        if ! hyprx_util_validate_snapshot_id "$SNAPSHOT_ID"; then
            hyprx_ui_error "Invalid snapshot ID format: $SNAPSHOT_ID"
            echo
            hyprx_ui_info "Use 'hyprx rollback list' to see available snapshots."
            exit 1
        fi

        if ! hyprx_snapshot_exists "$SNAPSHOT_ID"; then
            hyprx_ui_error "Unknown snapshot: $SNAPSHOT_ID"
            echo
            hyprx_ui_info "Use 'hyprx rollback list' to see available snapshots."
            exit 1
        fi

        hyprx_ui_section "Rolling back: $SNAPSHOT_ID"

        if hyprx_util_dry_run; then
            hyprx_ui_warn "Dry run - nothing was changed."
            hyprx_ui_info "Would roll back snapshot: $SNAPSHOT_ID"
            hyprx_snapshot_preview "$SNAPSHOT_ID"
            hyprx_event rollback.preview id="$SNAPSHOT_ID" \
                packages="$(hyprx_snapshot_packages "$SNAPSHOT_ID" 2>/dev/null | grep -c . || true)" \
                configs="$(hyprx_snapshot_configs "$SNAPSHOT_ID" 2>/dev/null | grep -c . || true)"
            exit 0
        fi

        if ! hyprx_util_confirm "Roll back $SNAPSHOT_ID? This removes packages and restores configs."; then
            hyprx_ui_info "Aborted."
            exit 0
        fi

        hyprx_rollback_run "$SNAPSHOT_ID"

        ;;

esac
