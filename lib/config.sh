#!/usr/bin/env bash

# shellcheck disable=SC1090

HYPRX_CONFIG_FILE="$HYPRX_CONFIG/hyprx.conf"

# Every key is prefixed. The loader `source`s this file straight into the
# global namespace, so an unprefixed key like `PACKAGE_MANAGER=auto` used to
# land as a global and shadow/collide with the detected value the package
# layer actually reads. Prefixing keeps config, detection and runtime state
# in separate namespaces.
HYPRX_CONFIG_THEME="default"
HYPRX_CONFIG_AUTO_CONFIRM="false"
HYPRX_CONFIG_ENABLE_GPU_OFFLOAD="true"
HYPRX_CONFIG_BACKUP_ON_DEPLOY="true"
HYPRX_CONFIG_LOG_LEVEL="info"
HYPRX_CONFIG_LOG_FILE=""
HYPRX_CONFIG_PACKAGE_MANAGER="auto"

# Config keys that may appear in hyprx.conf. Anything else in that file is
# reported as unknown rather than silently becoming a global.
HYPRX_CONFIG_KEYS=(
    HYPRX_CONFIG_THEME
    HYPRX_CONFIG_AUTO_CONFIRM
    HYPRX_CONFIG_ENABLE_GPU_OFFLOAD
    HYPRX_CONFIG_BACKUP_ON_DEPLOY
    HYPRX_CONFIG_LOG_LEVEL
    HYPRX_CONFIG_LOG_FILE
    HYPRX_CONFIG_PACKAGE_MANAGER
)

########################################
# Load configuration
########################################

hyprx_config_load() {

    if [[ -f "$HYPRX_CONFIG_FILE" ]]; then

        # Parse rather than `source`: a config file is data, and sourcing it
        # lets it run arbitrary code and clobber any variable in scope.
        local line
        local key
        local value

        while IFS= read -r line || [[ -n "$line" ]]; do

            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"

            [[ -z "$line" ]] && continue
            [[ "$line" != *=* ]] && continue

            key="${line%%=*}"
            value="${line#*=}"

            key="${key//[[:space:]]/}"
            value="${value%\"}"; value="${value#\"}"
            value="${value%\'}"; value="${value#\'}"

            # Accept both the prefixed and legacy bare spelling.
            case "$key" in
                HYPRX_CONFIG_*) ;;
                THEME)                  key=HYPRX_CONFIG_THEME ;;
                AUTO_CONFIRM)           key=HYPRX_CONFIG_AUTO_CONFIRM ;;
                ENABLE_GPU_OFFLOAD)     key=HYPRX_CONFIG_ENABLE_GPU_OFFLOAD ;;
                BACKUP_ON_DEPLOY)       key=HYPRX_CONFIG_BACKUP_ON_DEPLOY ;;
                LOG_LEVEL)              key=HYPRX_CONFIG_LOG_LEVEL ;;
                LOG_FILE)               key=HYPRX_CONFIG_LOG_FILE ;;
                PACKAGE_MANAGER)        key=HYPRX_CONFIG_PACKAGE_MANAGER ;;
                *)
                    hyprx_ui_warn "Unknown key in hyprx.conf: $key"
                    continue
                    ;;
            esac

            printf -v "$key" '%s' "$value"

        done <"$HYPRX_CONFIG_FILE"

    fi

    # LOG_FILE, when set, is the install failure log. Honoured here (rather
    # than in lib/installer/failure_logger.sh) because config.sh is sourced
    # first, so that file's `${HYPRX_FAILURE_LOG:-...}` default picks it up.
    if [[ -n "$HYPRX_CONFIG_LOG_FILE" ]]; then
        local expanded="${HYPRX_CONFIG_LOG_FILE/#\~/$HOME}"
        export HYPRX_FAILURE_LOG="$expanded"
    fi

    return 0

}

########################################
# Save configuration
########################################

hyprx_config_save() {

    local dir
    dir="$(dirname "$HYPRX_CONFIG_FILE")"
    mkdir -p "$dir"

    {
        echo "# HyprX configuration - written by hyprx_config_save()"
        local k
        for k in "${HYPRX_CONFIG_KEYS[@]}"; do
            printf '%s=%s\n' "$k" "${!k}"
        done
    } >"$HYPRX_CONFIG_FILE"

    return 0

}

########################################
# Get configuration value
########################################

hyprx_config_get() {

    # NOTE: build the name via a separate variable. Written as
    # "$HYPRX_CONFIG_$1" bash would parse `$HYPRX_CONFIG_` as one variable
    # name - the trailing underscore is a valid identifier character - and
    # never read $1 at all.
    local prefix="HYPRX_CONFIG_"
    local key="${prefix}${1}"

    local known
    for known in "${HYPRX_CONFIG_KEYS[@]}"; do
        if [[ "$known" == "$key" ]]; then
            printf '%s\n' "${!key}"
            return 0
        fi
    done

    return 1

}

########################################
# Set configuration value
########################################

hyprx_config_set() {

    # See the note in hyprx_config_get about the trailing underscore.
    local prefix="HYPRX_CONFIG_"
    local key="${prefix}${1}"
    local value="$2"

    local known
    for known in "${HYPRX_CONFIG_KEYS[@]}"; do
        if [[ "$known" == "$key" ]]; then
            printf -v "$key" '%s' "$value"
            hyprx_config_save
            return 0
        fi
    done

    return 1

}

########################################
# Automatically load config
########################################

hyprx_config_load
