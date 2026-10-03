#!/usr/bin/env bash

hyprx_engine_run() {
    # One gate, not two.
    #
    # preflight.sh and compatibility.sh each probed the same six facts and
    # disagreed about three of them - internet was fatal in one and advisory in
    # the other, `sudo -v` ran twice (and can prompt twice), and RAM was read
    # with two different divisors so "8GB" was compared against gigabytes while
    # "4GB" was compared against megabytes. See lib/installer/gate.sh.
    #
    # The banner is also printed here rather than inside the gate: four stages
    # each opened with their own header, so one install scrolled past five
    # copies of the same box.
    hyprx_ui_divider
    hyprx_ui_header
    hyprx_ui_divider

    hyprx_snapshot_init_id

    hyprx_install_gate || return 1

    if hyprx_recovery_has_state; then
        hyprx_ui_info "Previous installation detected."
        hyprx_recovery_resume || return 1
    else
        hyprx_resolver_resolve || return 1
    fi

    hyprx_validator_validate || return 1

    # A partial install must not abort here. Configs, the snapshot and the
    # report are exactly what the user needs in order to recover from a package
    # failure, so a non-zero return from the install stage is recorded and the
    # pipeline continues. It still changes the final exit code.
    local install_rc=0
    hyprx_install_packages_run || install_rc=$?

    hyprx_deploy_all || return 1

    # Fonts before services, because most of what the services manage is a GUI
    # that needs them to render. A failure here is recorded, not fatal.
    local fonts_rc=0
    hyprx_fonts_install || fonts_rc=$?

    # Services next to the package install, because a service whose package was
    # just installed is exactly what this stage enables. A failure here is
    # recorded rather than fatal: the configs are still worth deploying and the
    # user can enable the unit by hand.
    local services_rc=0
    hyprx_services_enable || services_rc=$?

    hyprx_ui_section "GPU offload"

    if ! hyprx_config_bool HYPRX_CONFIG_ENABLE_GPU_OFFLOAD; then
        hyprx_ui_info "Skipped (ENABLE_GPU_OFFLOAD=false)"
    elif hyprx_util_dry_run; then
        hyprx_util_would "run scripts/gpu-offload-setup.sh"
    else
        bash "$HYPRX_ROOT/scripts/gpu-offload-setup.sh" \
            || hyprx_ui_warn "GPU offload setup had issues (non-fatal)"
    fi

    if hyprx_util_dry_run; then
        hyprx_util_would "write a rollback snapshot (nothing to roll back to, since nothing changed)"
    else
        hyprx_snapshot_save
    fi

    hyprx_report_generate || return 1

    hyprx_ui_divider

    if hyprx_util_dry_run; then
        hyprx_ui_warn "Dry run complete - nothing was installed, deployed or changed."
        hyprx_ui_info "Re-run without --dry-run to apply."
        hyprx_ui_divider
        return 0
    fi

    local problems=0

    if (( install_rc != 0 )); then
        problems=$((problems + 1))
        hyprx_ui_error "Installation completed with errors."
        hyprx_ui_info "Some packages failed to install."
    fi

    if (( fonts_rc != 0 )); then
        problems=$((problems + 1))
        hyprx_ui_error "Caudex could not be installed."
        hyprx_ui_info "Check with: hyprx doctor --only fonts"
    fi

    if (( services_rc != 0 )); then
        problems=$((problems + 1))
        hyprx_ui_error "Some systemd services could not be enabled."
        hyprx_ui_info "Check with: hyprx doctor --only services"
    fi

    if (( problems > 0 )); then
        # Never "completed successfully" when something in the list above
        # failed. The configs and the snapshot are still in place, so this is a
        # partial state and re-running is the cheap way out.
        hyprx_ui_info "Configs were deployed and a rollback snapshot was saved."
        hyprx_ui_info "Fix the failures above, then re-run 'hyprx install'."
        hyprx_ui_info "Re-running is safe: already-installed packages are skipped."
        hyprx_ui_divider
        return 1
    fi

    hyprx_ui_success "Installation completed successfully."

    hyprx_ui_divider

    return 0
}
