#!/usr/bin/env bash

run_install_engine() {

    INSTALL_START_TIME=$(date +%s)

    ####################################
    # Preflight
    ####################################

    preflight || {

        error "Preflight failed."

        return 1

    }

    success "Preflight passed."

    ####################################
    # Compatibility
    ####################################

    check_compatibility || {

        error "Compatibility check failed."

        return 1

    }

    success "Compatibility passed."

    ####################################
    # Temporary profile
    ####################################

    SELECTED_MODULES=(

        desktop
        development
        networking

    )

    ####################################
    # Resume
    ####################################

    if has_install_state; then

        warn "Found interrupted installation."

        if resume_install; then

            success "Resume successful."

        else

            warn "Unable to resume."

            resolve_packages

        fi

    else

        resolve_packages

    fi

    ####################################
    # Validation
    ####################################

    validate_packages

    ####################################
    # Install
    ####################################

    install_packages

    ####################################
    # Report
    ####################################

    INSTALL_END_TIME=$(date +%s)

    INSTALL_DURATION=$((INSTALL_END_TIME-INSTALL_START_TIME))

    generate_report

    ####################################
    # Finished
    ####################################

    success "Ready."

}