#!/usr/bin/env bash

hyprx_engine_run() {
    hyprx_ui_divider
    hyprx_ui_header
    hyprx_ui_divider

    hyprx_snapshot_init_id

    hyprx_preflight_check || return 1
    hyprx_compatibility_check || return 1

    if hyprx_recovery_has_state; then
        hyprx_ui_info "Previous installation detected."
        hyprx_recovery_resume || return 1
    else
        hyprx_resolver_resolve || return 1
    fi

    hyprx_validator_validate || return 1
    hyprx_install_packages_run || return 1
    hyprx_deploy_all || return 1

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
    else
        hyprx_ui_success "Installation completed successfully."
    fi

    hyprx_ui_divider

    return 0
}
