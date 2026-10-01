#!/usr/bin/env bash

########################################
# hyprx install [--dry-run]
########################################
# --dry-run runs the entire pipeline - preflight, compatibility,
# resolution, validation, the install loop, config deploy - but every
# mutating helper checks hyprx_util_dry_run() and reports what it
# would have done instead of doing it. Nothing is installed, deployed,
# backed up or snapshotted.
#
# This exists so the install path is reachable from the test suite and
# from a paranoid pre-flight check, rather than only being discovered
# halfway through a real run.
#

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            export HYPRX_DRY_RUN=1
            ;;
        -h|--help)
            hyprx_ui_section "hyprx install"
            cat <<'EOF'
Usage:
    hyprx install [--dry-run]

Options:
    --dry-run   Run every stage and report what would change, without
                installing packages, deploying configs, taking a
                snapshot or enabling any services.
EOF
            exit 0
            ;;
        *)
            hyprx_ui_error "Unknown option: $arg"
            hyprx_ui_info "Run 'hyprx install --help' for usage."
            exit 1
            ;;
    esac
done

if hyprx_util_dry_run; then
    hyprx_ui_warn "DRY RUN - no packages will be installed, no configs deployed,"
    hyprx_ui_warn "no snapshot taken, no services enabled."
    echo
fi

hyprx_engine_run
