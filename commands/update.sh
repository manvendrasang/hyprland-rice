#!/usr/bin/env bash

# hyprx update
#
# Arguments are validated before anything happens. This used to ignore them,
# so `hyprx update --help` fell straight through to a real system upgrade -
# not a recoverable mistake, hence the guard.

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            hyprx_ui_section "hyprx update"
            cat <<'EOF'
Usage:
    hyprx update

Runs a full system update through the configured package manager, then
removes orphaned packages and cleans the package cache.

Takes no options. Note this performs a real system-wide upgrade.
EOF
            exit 0
            ;;
        *)
            hyprx_ui_error "Unknown option: $arg"
            hyprx_ui_info "'hyprx update' takes no options. Run 'hyprx update --help'."
            exit 1
            ;;
    esac
done

hyprx_ui_header
hyprx_logger_info "Starting system update"

start_time=$(date +%s)

hyprx_ui_info "Synchronizing package databases..."

# The manager-dispatch lives in lib/packages.sh. A non-zero return means
# either an unsupported manager or a failed update (cancelled sudo prompt,
# mirror error, conflict) - report which, rather than blaming the manager.
if [[ "$HYPRX_DETECT_PACKAGE_MANAGER" == "unknown" ]]; then
    hyprx_ui_error "No supported package manager (tried: yay, paru, pacman)"
    exit 1
fi

if ! hyprx_pkg_update_system; then
    hyprx_ui_error "Update failed via $HYPRX_DETECT_PACKAGE_MANAGER - see the output above"
    hyprx_ui_info "A common cause is an unanswered sudo password prompt; re-run in a terminal."
    exit 1
fi

echo

hyprx_ui_info "Checking for orphan packages..."

hyprx_pkg_remove_orphans

echo

hyprx_ui_info "Updating package cache..."

hyprx_pkg_clean_cache

echo

hyprx_ui_divider

end_time=$(date +%s)
elapsed=$((end_time - start_time))

hyprx_ui_success "System update completed."
hyprx_logger_success "System update completed successfully."

echo
printf "%-20s %ss\n" "Elapsed" "$elapsed"
