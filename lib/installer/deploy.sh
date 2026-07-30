#!/usr/bin/env bash

########################################
# Deploy a single config directory
########################################
#
# Backs up whatever already exists at the
# target before overwriting it, and records
# the outcome so rollback can undo it later.
#

deploy_config_dir() {

    local dir="$1"

    local source="$HYPRX_CONFIG/$dir"
    local target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"
    local staging="${target}.hyprx-staging.$$"

    if [[ ! -d "$source" ]]; then
        warn "Missing config source: $dir"
        return 1
    fi

    mkdir -p "$(dirname "$target")"

    # Build the full new config in a staging dir first. This can take
    # real time for large configs, so it must never happen with the
    # live target already removed - a config watcher (e.g. Hyprland's
    # live reload) could catch the target mid-copy or briefly missing.
    rm -rf "$staging"
    cp -r "$source" "$staging"

    if [[ -e "$target" ]]; then

        local backup
        backup="$(config_backup_dir_for "$(current_snapshot_id)")/$dir"

        mkdir -p "$(dirname "$backup")"
        rm -rf "$backup"

        # Swap: two fast renames instead of rm-then-copy, so the
        # target is only ever missing for a moment, not seconds.
        mv "$target" "$backup"
        mv "$staging" "$target"

        record_config_backup "$dir" "true"

        info "Backed up existing $dir"

    else

        mv "$staging" "$target"

        record_config_backup "$dir" "false"

    fi

    success "Deployed $dir"

}

########################################
# Deploy configs for a single module
########################################

deploy_module_config() {

    local module="$1"

    load_module "$module" || return 1

    [[ -n "${CONFIG_DIRS:-}" ]] || return 0

    local dir

    for dir in $CONFIG_DIRS; do
        deploy_config_dir "$dir"
    done

}

########################################
# Deploy configs for every selected module
########################################

deploy_configs() {

    section "Deploying configuration"

    local module

    for module in "${SELECTED_MODULES[@]}"; do
        deploy_module_config "$module"
    done

}
