#!/usr/bin/env bash

HYPRX_RETRY_MAX=3
HYPRX_RETRY_BASE_DELAY=2

# hyprx_retry <max_attempts> <command> [args...]
hyprx_retry() {
    local max_attempts="$1"
    shift

    local attempt=1

    until "$@"; do
        (( attempt >= max_attempts )) && return 1

        attempt=$((attempt + 1))
        sleep "$HYPRX_RETRY_BASE_DELAY"
    done

    return 0
}

hyprx_retry_failed_packages() {
    [[ ${#HYPRX_INSTALL_FAILED[@]} -eq 0 ]] && return 0

    local remaining=("${HYPRX_INSTALL_FAILED[@]}")
    local attempt delay pkg status current_failed

    HYPRX_INSTALL_FAILED=()

    for ((attempt = 1; attempt <= HYPRX_RETRY_MAX; attempt++)); do
        [[ ${#remaining[@]} -eq 0 ]] && break

        hyprx_ui_divider
        hyprx_ui_info "Retry attempt $attempt/$HYPRX_RETRY_MAX"

        current_failed=()

        for pkg in "${remaining[@]}"; do
            hyprx_ui_info "Retrying $pkg"

            # `if`, not `cmd; status=$?` - see the note in
            # install_packages.sh about the errexit leak this used to cause.
            if hyprx_pkg_install "$pkg"; then
                status=0
            else
                status=$?
            fi

            case "$status" in
                0)
                    hyprx_ui_success "$pkg"
                    HYPRX_INSTALL_INSTALLED+=("$pkg")
                    hyprx_recovery_mark_complete "$pkg"
                    ;;
                10)
                    hyprx_ui_info "$pkg already installed."
                    HYPRX_INSTALL_SKIPPED+=("$pkg")
                    hyprx_recovery_mark_complete "$pkg"
                    ;;
                *)
                    hyprx_ui_warn "$pkg failed again"
                    current_failed+=("$pkg")
                    hyprx_failure_logger_log "$pkg" "Retry $attempt failed"
                    ;;
            esac
        done

        remaining=("${current_failed[@]}")
        [[ ${#remaining[@]} -eq 0 ]] && break

        if (( attempt < HYPRX_RETRY_MAX )); then
            delay=$((HYPRX_RETRY_BASE_DELAY ** attempt))
            hyprx_ui_warn "Waiting ${delay}s before next retry..."
            sleep "$delay"
        fi
    done

    HYPRX_INSTALL_FAILED=("${remaining[@]}")

    if (( ${#HYPRX_INSTALL_FAILED[@]} == 0 )); then
        hyprx_ui_success "All failed packages recovered."
    else
        hyprx_ui_warn "Some packages could not be installed."
    fi
}
