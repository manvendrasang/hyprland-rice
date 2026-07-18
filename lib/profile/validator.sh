#!/usr/bin/env bash

########################################
# Validate profile
########################################

validate_profile() {

    local profile="$1"

    profile_exists "$profile" || {
        error "Unknown profile: $profile"
        return 1
    }

    local profile_dir="$HYPRX_PROFILES/$profile"

    [[ -f "$profile_dir/profile.conf" ]] || {
        error "Missing profile.conf"
        return 1
    }

    [[ -f "$profile_dir/modules.list" ]] || {
        error "Missing modules.list"
        return 1
    }

    local module
    local failed=0

    declare -A seen=()

    while IFS= read -r module || [[ -n "$module" ]]; do

        [[ -z "$module" ]] && continue
        [[ "$module" =~ ^# ]] && continue

        if [[ -n "${seen[$module]:-}" ]]; then
            warn "Duplicate module: $module"
            continue
        fi

        seen["$module"]=1

        if [[ ! -d "$HYPRX_MODULES/$module" ]]; then
            error "Module '$module' does not exist."
            failed=1
        fi

    done < "$profile_dir/modules.list"

    if (( failed )); then
        return 1
    fi

    success "Profile validation passed."

    return 0

}