#!/usr/bin/env bash

# shellcheck disable=SC1090

########################################
# Discover modules
########################################

discover_modules() {

    AVAILABLE_MODULES=()

    [[ -d "$HYPRX_MODULES" ]] || return 1

    local dir

    for dir in "$HYPRX_MODULES"/*; do
        [[ -d "$dir" ]] || continue
        AVAILABLE_MODULES+=("$(basename "$dir")")
    done

    return 0

}

########################################
# Module exists
########################################

module_exists() {

    [[ -d "$HYPRX_MODULES/$1" ]]

}

########################################
# Load module
########################################

load_module() {

    local module="$1"

    module_exists "$module" || {
        error "Unknown module: $module"
        return 1
    }

    local conf="$HYPRX_MODULES/$module/module.conf"

    [[ -f "$conf" ]] || {
        error "Missing module.conf: $module"
        return 1
    }

    unset NAME
    unset DESCRIPTION
    unset OPTIONAL
    unset DEPENDENCIES
    unset PACKAGE_FILE
    unset SERVICE_FILE
    unset CONFIG_DIRS

    source "$conf"

    NAME="${NAME:-}"
    DESCRIPTION="${DESCRIPTION:-}"
    OPTIONAL="${OPTIONAL:-true}"
    DEPENDENCIES="${DEPENDENCIES:-}"
    PACKAGE_FILE="${PACKAGE_FILE:-}"
    SERVICE_FILE="${SERVICE_FILE:-}"
    CONFIG_DIRS="${CONFIG_DIRS:-}"

    [[ -n "$NAME" && -n "$PACKAGE_FILE" ]] || {
        warn "Incomplete module.conf: $module (missing NAME or PACKAGE_FILE)"
        return 1
    }

    return 0

}

########################################
# Print module
########################################

print_module() {

    local module="$1"

    load_module "$module" || return 1

    echo "Name         : $NAME"
    echo "Description  : $DESCRIPTION"
    echo "Optional     : $OPTIONAL"
    echo "Dependencies : ${DEPENDENCIES:-None}"
    echo "Packages     : $PACKAGE_FILE"
    echo "Services     : ${SERVICE_FILE:-None}"
    echo "Configs      : ${CONFIG_DIRS:-None}"

}