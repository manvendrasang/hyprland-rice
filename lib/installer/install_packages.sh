#!/usr/bin/env bash

hyprx_install_packages_run() {

    hyprx_ui_header
    hyprx_ui_info "Installing packages..."

    HYPRX_INSTALL_INSTALLED=()
    HYPRX_INSTALL_SKIPPED=()
    HYPRX_INSTALL_FAILED=()

    HYPRX_INSTALL_START_TIME=$(date +%s)

    hyprx_recovery_save_state

    for pkg in "${HYPRX_INSTALL_QUEUE[@]}"; do

        hyprx_ui_info "Installing $pkg"

        set +e
        hyprx_pkg_install "$pkg"
        status=$?
        set -e

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
        hyprx_ui_error "$pkg"
        HYPRX_INSTALL_FAILED+=("$pkg")
        hyprx_failure_logger_log "$pkg" "Installation failed"
        ;;
esac

    done

    ####################################################
    # Retry
    ####################################################

    if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then

        hyprx_ui_divider

        hyprx_ui_warn "Retrying failed packages..."

        hyprx_retry_failed_packages

    fi

    ####################################################
    # Summary
    ####################################################

    HYPRX_INSTALL_END_TIME=$(date +%s)
    HYPRX_INSTALL_DURATION=$((HYPRX_INSTALL_END_TIME-HYPRX_INSTALL_START_TIME))

    hyprx_ui_divider

    hyprx_ui_success "Installation Summary"

    echo

    printf "%-12s : %d\n" "Installed" "${#HYPRX_INSTALL_INSTALLED[@]}"
    printf "%-12s : %d\n" "Skipped"   "${#HYPRX_INSTALL_SKIPPED[@]}"
    printf "%-12s : %d\n" "Failed"    "${#HYPRX_INSTALL_FAILED[@]}"

    printf "%-12s : %02d:%02d\n" \
        "Duration" \
        "$((HYPRX_INSTALL_DURATION/60))" \
        "$((HYPRX_INSTALL_DURATION%60))"

    echo

    ####################################################
    # Failed Packages
    ####################################################

    if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then

        hyprx_ui_warn "Packages still failing"

        echo

        for pkg in "${HYPRX_INSTALL_FAILED[@]}"; do
            echo " • $pkg"
        done

        echo

        hyprx_ui_warn "Failure log"

        echo " $HYPRX_FAILURE_LOG"

    else

        hyprx_ui_success "All packages installed successfully."

    fi

    ####################################################
    # Cleanup
    ####################################################

    if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then
        hyprx_failure_logger_summary
    fi

    hyprx_recovery_clear_state

}
