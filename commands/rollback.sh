#!/usr/bin/env bash

ACTION="${1:-help}"

case "$ACTION" in

    list)

        section "Available Snapshots"

        if [[ -z "$(list_snapshots)" ]]; then
            info "No snapshots found."
        else
            list_snapshots
        fi

        ;;

    latest)

        SNAPSHOT_ID="$(latest_snapshot)"

        [[ -z "$SNAPSHOT_ID" ]] && {
            info "No snapshots found."
            exit 0
        }

        section "Rolling back: $SNAPSHOT_ID"

        rollback_snapshot "$SNAPSHOT_ID"

        ;;

    "")

        section "Rollback"

        info "No snapshot specified. Use 'hyprx rollback list' to see options."

        ;;

    help)

        section "Rollback"

        cat <<EOF
Usage:
    hyprx rollback list           Show available snapshots
    hyprx rollback latest         Roll back the most recent install
    hyprx rollback <snapshot-id>  Roll back a specific snapshot

Notes:
    Only packages newly installed by HyprX in that run are removed.
    Packages that were already on your system before that install
    are never touched.
EOF
        ;;

    *)

        SNAPSHOT_ID="$ACTION"

        if ! snapshot_exists "$SNAPSHOT_ID"; then
            error "Unknown snapshot: $SNAPSHOT_ID"
            echo
            info "Use 'hyprx rollback list' to see available snapshots."
            exit 1
        fi

        section "Rolling back: $SNAPSHOT_ID"

        rollback_snapshot "$SNAPSHOT_ID"

        ;;

esac
