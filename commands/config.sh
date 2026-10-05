#!/usr/bin/env bash

# hyprx config <list|get|set|unset|path>
#
# Values are validated before being written, so a typo (LOG_LEVEL=verbose) is
# rejected at the point of the mistake rather than silently doing nothing.

ACTION="${1:-list}"
shift || true

usage() {
    cat <<'EOF'
Usage:
    hyprx config list [--json]        Show every key and its current value
    hyprx config get <KEY> [--json]   Print one value
    hyprx config set <KEY> <VALUE>    Change a value (validated)
    hyprx config unset <KEY>          Restore a key to its default
    hyprx config path                 Print the config file location

Keys:
    THEME               Waybar theme name (must exist in config/waybar/themes/)
    AUTO_CONFIRM        true|false - answer yes to confirmations
    BACKUP_ON_DEPLOY    true|false - back up existing configs before replacing
    ENABLE_GPU_OFFLOAD  true|false - run GPU offload setup during install
    LOG_LEVEL           off|error|warn|info|debug
    LOG_FILE            Path to the install failure log (default: state dir)
    PACKAGE_MANAGER     auto|pacman|yay|paru
EOF
}

case "$ACTION" in

    list)
        if [[ "${1:-}" == "--json" ]]; then
            hyprx_config_list_json
            exit 0
        fi
        hyprx_ui_section "Configuration"
        hyprx_config_list
        echo
        hyprx_ui_info "File: $HYPRX_CONFIG_FILE"
        ;;

    get)
        KEY="${1:-}"
        if [[ -z "$KEY" ]]; then
            hyprx_ui_error "Missing key."
            usage
            exit 1
        fi
        if ! VALUE="$(hyprx_config_get "$KEY")"; then
            hyprx_ui_error "Unknown key: $KEY"
            hyprx_ui_info "Valid keys: $(printf '%s ' "${!HYPRX_CONFIG_KEYS[@]}" | sed 's/HYPRX_CONFIG_//g')"
            exit 1
        fi
        if [[ "${2:-}" == "--json" ]]; then
            printf '{"key":"%s","value":"%s"}\n' \
                "$(hyprx_event_escape "$KEY")" "$(hyprx_event_escape "$VALUE")"
            exit 0
        fi
        printf '%s\n' "$VALUE"
        ;;

    set)
        KEY="${1:-}"
        VALUE="${2:-}"
        if [[ -z "$KEY" || -z "${2+x}" ]]; then
            hyprx_ui_error "Usage: hyprx config set <KEY> <VALUE>"
            usage
            exit 1
        fi

        # hyprx_config_set validates before it writes and returns:
        #   0 written, 1 unknown key, 2 invalid value
        #
        # It used to be called with no validation and this block validated
        # afterwards, then "reverted" the bad write with hyprx_config_unset -
        # which restores the DEFAULT rather than the previous value. A rejected
        # set therefore destroyed whatever was there before.
        hyprx_config_set "$KEY" "$VALUE"
        case "$?" in
            0)
                hyprx_ui_success "$KEY = $VALUE"
                hyprx_logger_success "config set $KEY=$VALUE"
                hyprx_event config.changed key="$KEY" value="$VALUE"
                ;;
            2)
                hyprx_ui_error "Invalid value for $KEY: '$VALUE'"
                hyprx_ui_info "Value not written. $(hyprx_config_current_is "$KEY")"
                hyprx_ui_info "Valid values: hyprx config --help"
                exit 1
                ;;
            *)
                hyprx_ui_error "Unknown key: $KEY"
                hyprx_ui_info "Valid keys: $(printf '%s ' "${!HYPRX_CONFIG_KEYS[@]}" | sed 's/HYPRX_CONFIG_//g')"
                usage
                exit 1
                ;;
        esac
        ;;

    unset)
        KEY="${1:-}"
        if [[ -z "$KEY" ]]; then
            hyprx_ui_error "Missing key."
            usage
            exit 1
        fi
        if hyprx_config_unset "$KEY"; then
            hyprx_ui_success "$KEY reset to default ($(hyprx_config_get "$KEY"))"
            hyprx_event config.changed key="$KEY" value="$(hyprx_config_get "$KEY")"
        else
            hyprx_ui_error "Unknown key: $KEY"
            hyprx_ui_info "Valid keys: $(printf '%s ' "${!HYPRX_CONFIG_KEYS[@]}" | sed 's/HYPRX_CONFIG_//g')"
            exit 1
        fi
        ;;

    path)
        printf '%s\n' "$HYPRX_CONFIG_FILE"
        ;;

    -h|--help|help)
        usage
        ;;

    *)
        hyprx_ui_error "Unknown action: $ACTION"
        usage
        exit 1
        ;;
esac
