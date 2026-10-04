#!/usr/bin/env bash

ACTION="${1:-help}"

case "$ACTION" in

    list)

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
            exit 0
        fi

        if ! hyprx_util_confirm "Roll back $SNAPSHOT_ID? This removes packages and restores configs."; then
            hyprx_ui_info "Aborted."
            exit 0
        fi

        hyprx_snapshot_rollback "$SNAPSHOT_ID"

        ;;

    "")

        hyprx_ui_section "Rollback"

        hyprx_ui_info "No snapshot specified. Use 'hyprx rollback list' to see options."

        ;;

    help)

        hyprx_ui_section "Rollback"

        cat <<EOF
Usage:
    hyprx rollback list           Show available snapshots
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
            exit 0
        fi

        if ! hyprx_util_confirm "Roll back $SNAPSHOT_ID? This removes packages and restores configs."; then
            hyprx_ui_info "Aborted."
            exit 0
        fi

        hyprx_snapshot_rollback "$SNAPSHOT_ID"

        ;;

esac
