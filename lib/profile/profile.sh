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
# Create profile
########################################

create_profile() {

    local id="$1"
    local name="$2"
    local description="$3"
    shift 3
    local modules=("$@")

    if [[ -z "$id" ]]; then
        error "Profile id is required."
        return 1
    fi

    if profile_exists "$id"; then
        error "Profile already exists: $id"
        return 1
    fi

    if (( ${#modules[@]} == 0 )); then
        error "At least one module is required."
        return 1
    fi

    local module

    for module in "${modules[@]}"; do
        if [[ ! -d "$HYPRX_MODULES/$module" ]]; then
            error "Module '$module' does not exist."
            return 1
        fi
    done

    local dir="$PROFILE_ROOT/$id"

    mkdir -p "$dir"

    {
        echo "NAME=${name:-$id}"
        echo "ID=$id"
        echo "DESCRIPTION=${description:-}"
        echo "VERSION=1.0"
    } > "$dir/profile.conf"

    printf "%s\n" "${modules[@]}" > "$dir/modules.list"

    if ! validate_profile "$id"; then
        error "Profile failed validation after creation, removing."
        rm -rf "$dir"
        return 1
    fi

    success "Profile created: $id"

}

profile_modules() {

    local profile="$1"

    profile_exists "$profile" || return 1

    local file="$PROFILE_ROOT/$profile/modules.list"

    [[ -f "$file" ]] || return 1

    cat "$file"

}