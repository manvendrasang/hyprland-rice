#!/usr/bin/env bash

# shellcheck disable=SC1090

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

    source "$conf"

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

}