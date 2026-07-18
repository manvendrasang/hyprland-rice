#!/usr/bin/env bash

PROFILE_ROOT="$HYPRX_PROFILES"

########################################
# Discover available profiles
########################################

discover_profiles() {

    AVAILABLE_PROFILES=()

    [[ -d "$PROFILE_ROOT" ]] || return 1

    local dir

    for dir in "$PROFILE_ROOT"/*; do
        [[ -d "$dir" ]] || continue
        AVAILABLE_PROFILES+=("$(basename "$dir")")
    done

    return 0

}

########################################
# Profile exists?
########################################

profile_exists() {

    local profile="$1"

    [[ -d "$PROFILE_ROOT/$profile" ]]

}

########################################
# Load profile
########################################

load_profile() {

    local profile="$1"

    [[ -z "$profile" ]] && {
        error "No profile specified."
        return 1
    }

    if ! profile_exists "$profile"; then
        error "Unknown profile: $profile"
        return 1
    fi

    local file="$PROFILE_ROOT/$profile/modules.list"

    [[ -f "$file" ]] || {
        error "Missing modules.list for profile '$profile'."
        return 1
    }

    validate_profile "$profile" || return 1

    CURRENT_PROFILE="$profile"
    export CURRENT_PROFILE

    SELECTED_MODULES=()

    while IFS= read -r module || [[ -n "$module" ]]; do
        [[ -z "$module" ]] && continue
        [[ "$module" =~ ^# ]] && continue
        SELECTED_MODULES+=("$module")
    done < "$file"

    return 0

}

########################################
# Current profile
########################################

current_profile() {

    echo "${CURRENT_PROFILE:-$PROFILE}"

}

########################################
# Print profile information
########################################

print_profile() {

    local profile="$1"

    profile_exists "$profile" || return 1

    local conf="$PROFILE_ROOT/$profile/profile.conf"

    [[ -f "$conf" ]] || return 1

    cat "$conf"

}

########################################
# Print profile modules
########################################

profile_modules() {

    local profile="$1"

    profile_exists "$profile" || return 1

    local file="$PROFILE_ROOT/$profile/modules.list"

    [[ -f "$file" ]] || return 1

    cat "$file"

}