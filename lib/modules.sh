#!/usr/bin/env bash

MODULE_ROOT="$ROOT_DIR/modules"

AVAILABLE_MODULES=()

# --------------------------------------------------
# Discovery
# --------------------------------------------------

discover_modules() {

    AVAILABLE_MODULES=()

    [[ -d "$MODULE_ROOT" ]] || return

    while IFS= read -r -d '' dir; do
        AVAILABLE_MODULES+=("$(basename "$dir")")
    done < <(find "$MODULE_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

}

# --------------------------------------------------
# Validation
# --------------------------------------------------

module_exists() {

    [[ -d "$MODULE_ROOT/$1" ]]

}

module_validate() {

    local module="$1"

    [[ -f "$MODULE_ROOT/$module/module.conf" ]] || return 1
    [[ -f "$MODULE_ROOT/$module/packages.list" ]] || return 2
    [[ -f "$MODULE_ROOT/$module/services.list" ]] || return 3

    return 0
}

# --------------------------------------------------
# Loading
# --------------------------------------------------

module_load() {

    local module="$1"

    module_exists "$module" || return 1

    source "$MODULE_ROOT/$module/module.conf"

}

# --------------------------------------------------
# Packages
# --------------------------------------------------

module_packages() {

    local module="$1"

    [[ -f "$MODULE_ROOT/$module/packages.list" ]] || return

    while IFS='|' read -r package source; do

        [[ -z "$package" ]] && continue
        [[ "$package" =~ ^# ]] && continue

        printf "%s|%s\n" "$package" "$source"

    done < "$MODULE_ROOT/$module/packages.list"

}

# --------------------------------------------------
# Services
# --------------------------------------------------

module_services() {

    local module="$1"

    [[ -f "$MODULE_ROOT/$module/services.list" ]] || return

    grep -v '^#' "$MODULE_ROOT/$module/services.list" | grep -v '^$'

}

# --------------------------------------------------
# Dependencies
# --------------------------------------------------

module_dependencies() {

    local module="$1"

    module_load "$module" || return

    echo "$DEPENDENCIES"

}