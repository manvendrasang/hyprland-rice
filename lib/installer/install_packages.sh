#!/usr/bin/env bash

install_packages() {

    header
    info "Installing packages..."

    INSTALLED_PACKAGES=()
    SKIPPED_PACKAGES=()
    FAILED_PACKAGES=()

    INSTALL_START_TIME=$(date +%s)

    save_install_state

    for pkg in "${PACKAGE_QUEUE[@]}"; do

        info "Installing $pkg"

        set +e
        install_package "$pkg"
        status=$?
        set -e

        case "$status" in

    0)
        success "$pkg"
        INSTALLED_PACKAGES+=("$pkg")
        mark_package_complete "$pkg"
        ;;

    10)
        info "$pkg already installed."
        SKIPPED_PACKAGES+=("$pkg")
        mark_package_complete "$pkg"
        ;;

    *)
        error "$pkg"
        FAILED_PACKAGES+=("$pkg")
        log_failed_package "$pkg" "Installation failed"
        ;;
esac

    done

    ####################################################
    # Retry
    ####################################################

    if (( ${#FAILED_PACKAGES[@]} > 0 )); then

        divider

        warn "Retrying failed packages..."

        retry_failed_packages

    fi

    ####################################################
    # Summary
    ####################################################

    INSTALL_END_TIME=$(date +%s)
    INSTALL_DURATION=$((INSTALL_END_TIME-INSTALL_START_TIME))

    divider

    success "Installation Summary"

    echo

    printf "%-12s : %d\n" "Installed" "${#INSTALLED_PACKAGES[@]}"
    printf "%-12s : %d\n" "Skipped"   "${#SKIPPED_PACKAGES[@]}"
    printf "%-12s : %d\n" "Failed"    "${#FAILED_PACKAGES[@]}"

    printf "%-12s : %02d:%02d\n" \
        "Duration" \
        "$((INSTALL_DURATION/60))" \
        "$((INSTALL_DURATION%60))"

    echo

    ####################################################
    # Failed Packages
    ####################################################

    if (( ${#FAILED_PACKAGES[@]} > 0 )); then

        warn "Packages still failing"

        echo

        for pkg in "${FAILED_PACKAGES[@]}"; do
            echo " • $pkg"
        done

        echo

        warn "Failure log"

        echo " $FAILURE_LOG"

    else

        success "All packages installed successfully."

    fi

    ####################################################
    # Cleanup
    ####################################################

    if (( ${#FAILED_PACKAGES[@]} > 0 )); then
        log_failure_summary
    fi

    clear_install_state

}