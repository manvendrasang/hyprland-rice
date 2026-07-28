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

    if [[ ! -d "$source" ]]; then
        warn "Missing config source: $dir"
        return 1
    fi

    mkdir -p "$(dirname "$target")"

    if [[ -e "$target" ]]; then

        local backup
        backup="$(config_backup_dir_for "$(current_snapshot_id)")/$dir"

        mkdir -p "$(dirname "$backup")"
        rm -rf "$backup"
        cp -r "$target" "$backup"

        record_config_backup "$dir" "true"

        info "Backed up existing $dir"

    else

        record_config_backup "$dir" "false"

    fi

    rm -rf "$target"
    cp -r "$source" "$target"

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
