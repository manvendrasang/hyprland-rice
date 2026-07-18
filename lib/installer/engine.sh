#!/usr/bin/env bash

run_install_engine() {

    divider
    header "HyprX Installer"
    divider

    #
    # Load profile
    #

    info "Loading profile: $PROFILE"

    load_profile "$PROFILE" || return 1

    #
    # Preflight
    #

    preflight || return 1

    #
    # Compatibility
    #

    check_compatibility || return 1

    #
    # Resume installation if available
    #

    if has_install_state; then
        info "Previous installation detected."

        resume_install || return 1
    else
        resolve_packages || return 1
    fi

    #
    # Validate packages
    #

    validate_packages || return 1

    #
    # Install packages
    #

    install_packages || return 1

    #
    # Generate report
    #

    generate_report || return 1

    divider
    success "Installation completed successfully."
    divider

    return 0
}