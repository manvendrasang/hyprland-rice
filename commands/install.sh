#!/usr/bin/env bash

# --dry-run runs the whole pipeline but every mutating helper checks
# hyprx_util_dry_run() and reports instead of acting, so the install path is
# reachable from the test suite and from a pre-flight check.

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

# Install mutates install.state, snapshots and deployed configs - it must not
# run alongside another writer (a second terminal, a future GUI, or itself).
# Released by the process EXIT trap (see lib/elevate.sh).
hyprx_lock_acquire || exit 3

hyprx_engine_run
