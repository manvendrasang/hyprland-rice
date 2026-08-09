#!/usr/bin/env bash

# shellcheck disable=SC1090

CONFIG_FILE="$HYPRX_CONFIG/hyprx.conf"

########################################
# Load configuration
########################################

load_config() {

    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    THEME="${THEME:-default}"

    export THEME

    return 0

}

########################################
# Save configuration
########################################

save_config() {

    cat > "$CONFIG_FILE" <<CONFEOF
THEME=$THEME
CONFEOF

    return 0

}

########################################
# Get configuration value
########################################

get_config() {

    local key="$1"

    case "$key" in
        THEME)
            echo "$THEME"
            ;;
        *)
            return 1
            ;;
    esac

}

########################################
# Set configuration value
########################################

set_config() {

    local key="$1"
    local value="$2"

    case "$key" in
        THEME)
            THEME="$value"
            ;;
        *)
            return 1
            ;;
    esac

    save_config

    return 0

}

########################################
# Automatically load config
########################################

load_config
