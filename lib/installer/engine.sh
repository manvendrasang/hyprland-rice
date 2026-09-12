#!/usr/bin/env bash

run_install_engine() {

    divider
    header "HyprX Installer"
    divider

    #
    # Snapshot id for this run
    #
    # Must happen via direct call, not $(...),
    # so the id genuinely persists for every
    # later read in this same install run.
    #

    init_snapshot_id

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
    # Deploy configs
    #

    deploy_configs || return 1

    #
    # GPU offload for known heavy apps
    #
    # Best-effort: never fails the install if
    # something about a specific .desktop file
    # is unexpected - offload is a convenience,
    # not a hard requirement.
    #

    section "GPU offload"
    bash "$ROOT_DIR/scripts/gpu-offload-setup.sh" || warn "GPU offload setup had issues (non-fatal)"

    #
    # Snapshot
    #

    save_snapshot

    #
    # Generate report
    #

    generate_report || return 1

    divider
    success "Installation completed successfully."
    divider

    return 0
}