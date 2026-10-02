#!/usr/bin/env bash

# shellcheck disable=SC1090

HYPRX_CONFIG_FILE="$HYPRX_CONFIG/hyprx.conf"

# Every key is prefixed so config cannot collide with runtime state - an
# unprefixed `PACKAGE_MANAGER=auto` in hyprx.conf used to land as a global and
# shadow the value the package layer actually reads.
HYPRX_CONFIG_THEME="default"
HYPRX_CONFIG_AUTO_CONFIRM="false"
HYPRX_CONFIG_ENABLE_GPU_OFFLOAD="true"
HYPRX_CONFIG_BACKUP_ON_DEPLOY="true"
HYPRX_CONFIG_LOG_LEVEL="info"
HYPRX_CONFIG_LOG_FILE=""
HYPRX_CONFIG_PACKAGE_MANAGER="auto"

HYPRX_CONFIG_KEYS=(
    HYPRX_CONFIG_THEME
    HYPRX_CONFIG_AUTO_CONFIRM
    HYPRX_CONFIG_ENABLE_GPU_OFFLOAD
    HYPRX_CONFIG_BACKUP_ON_DEPLOY
    HYPRX_CONFIG_LOG_LEVEL
    HYPRX_CONFIG_LOG_FILE
    HYPRX_CONFIG_PACKAGE_MANAGER
)

hyprx_config_load() {
    local line key value

    if [[ -f "$HYPRX_CONFIG_FILE" ]]; then
        # Parsed, not sourced: hyprx.conf is data, and sourcing it would let it
        # run arbitrary code in this scope.
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

            # Accept the prefixed spelling and the legacy bare one.
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

    # Honoured here because config.sh is sourced before
    # lib/installer/failure_logger.sh, whose default then picks it up.
    if [[ -n "$HYPRX_CONFIG_LOG_FILE" ]]; then
        export HYPRX_FAILURE_LOG="${HYPRX_CONFIG_LOG_FILE/#\~/$HOME}"
    fi

    return 0
}

hyprx_config_save() {
    mkdir -p "$(dirname "$HYPRX_CONFIG_FILE")"

    {
        echo "# HyprX configuration - written by hyprx_config_save()"
        local k
        for k in "${HYPRX_CONFIG_KEYS[@]}"; do
            printf '%s=%s\n' "$k" "${!k}"
        done
    } >"$HYPRX_CONFIG_FILE"

    return 0
}

# Build the key name via a separate variable: written as "$HYPRX_CONFIG_$1",
# bash absorbs the trailing underscore into the variable name and never reads
# $1 at all.
hyprx_config_key_of() {
    printf 'HYPRX_CONFIG_%s' "$1"
}

hyprx_config_get() {
    local key known
    key="$(hyprx_config_key_of "$1")"

    for known in "${HYPRX_CONFIG_KEYS[@]}"; do
        if [[ "$known" == "$key" ]]; then
            printf '%s\n' "${!key}"
            return 0
        fi
    done

    return 1
}

hyprx_config_set() {
    local key known
    key="$(hyprx_config_key_of "$1")"

    for known in "${HYPRX_CONFIG_KEYS[@]}"; do
        if [[ "$known" == "$key" ]]; then
            printf -v "$key" '%s' "$2"
            hyprx_config_save
            return 0
        fi
    done

    return 1
}

hyprx_config_unset() {
    local key default
    key="$(hyprx_config_key_of "$1")"

    default="$(hyprx_config_default_value "$1")" || return 1

    printf -v "$key" '%s' "$default"
    hyprx_config_save
    return 0
}

hyprx_config_default_value() {
    case "$(hyprx_config_key_of "$1")" in
        HYPRX_CONFIG_THEME)              printf 'default\n' ;;
        HYPRX_CONFIG_AUTO_CONFIRM)       printf 'false\n' ;;
        HYPRX_CONFIG_ENABLE_GPU_OFFLOAD) printf 'true\n' ;;
        HYPRX_CONFIG_BACKUP_ON_DEPLOY)   printf 'true\n' ;;
        HYPRX_CONFIG_LOG_LEVEL)          printf 'info\n' ;;
        HYPRX_CONFIG_LOG_FILE)           printf '\n' ;;
        HYPRX_CONFIG_PACKAGE_MANAGER)    printf 'auto\n' ;;
        *) return 1 ;;
    esac
}

hyprx_config_validate() {
    local key="$1" value="$2"

    case "$key" in
        THEME)
            # Must exist, or it is a typo that silently does nothing.
            [[ "$value" == "default" || -d "${HYPRX_CONFIG:?}/waybar/themes/$value" ]] || return 1
            ;;
        AUTO_CONFIRM|BACKUP_ON_DEPLOY|ENABLE_GPU_OFFLOAD)
            [[ "$value" == "true" || "$value" == "false" ]] || return 1
            ;;
        LOG_LEVEL)
            case "$value" in
                off|error|warn|info|debug) ;;
                *) return 1 ;;
            esac
            ;;
        PACKAGE_MANAGER)
            case "$value" in
                auto|pacman|yay|paru) ;;
                *) return 1 ;;
            esac
            ;;
        LOG_FILE)
            [[ -z "$value" || "$value" == /* || "$value" == ~/* ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

hyprx_config_list() {
    local k
    for k in "${HYPRX_CONFIG_KEYS[@]}"; do
        printf '%-32s %s\n' "${k#HYPRX_CONFIG_}" "${!k}"
    done
}

# Boolean value of a config key, by variable name.
hyprx_config_bool() {
    [[ "${!1}" == "true" ]]
}

hyprx_config_load
