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

# Remove a trailing comment from one config line.
#
# Quotes are tracked so a '#' inside "..." or '...' is literal. An unterminated
# quote runs to end of line rather than swallowing the whole file, which is the
# failure mode a naive state machine has.
hyprx_config_strip_comment() {
    local line="$1"
    local -i i=0
    local n=${#line}
    local char quote=""

    while (( i < n )); do
        char="${line:i:1}"

        case "$char" in
            '"'|"'")
                if [[ -z "$quote" ]]; then
                    quote="$char"
                elif [[ "$quote" == "$char" ]]; then
                    quote=""
                fi
                ;;
            '#')
                # Only a comment when not inside quotes.
                if [[ -z "$quote" ]]; then
                    printf '%s' "${line:0:i}"
                    return 0
                fi
                ;;
        esac

        i=$((i + 1))
    done

    printf '%s' "$line"
}

hyprx_config_load() {
    local line key value

    if [[ -f "$HYPRX_CONFIG_FILE" ]]; then
        # Parsed, not sourced: hyprx.conf is data, and sourcing it would let it
        # run arbitrary code in this scope.
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Strip a comment, but not one that is inside quotes. This is what
            # allows a value such as LOG_FILE="/var/log/my#app/hyprx.log" to
            # round-trip - the naive `line="${line%%#*}"` truncated it to
            # "/var/log/my".
            line="$(hyprx_config_strip_comment "$line")"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"

            [[ -z "$line" ]] && continue
            [[ "$line" != *=* ]] && continue

            key="${line%%=*}"
            value="${line#*=}"

            # Strip whitespace from the key and one layer of matching quotes
            # from the value.
            #
            # The comment strip above is naive on purpose and safe in
            # practice: a `#` inside a value is only preserved when the value
            # is quoted, which is the convention this file documents. `line` is
            # walked char by char so a `#` inside quotes is skipped rather than
            # truncating the value - 'my#log.txt' used to store as 'my'.
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
        export HYPRX_FAILURE_LOG_OVERRIDE="${HYPRX_CONFIG_LOG_FILE/#\~/$HOME}"
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

    # The key must exist before the value is considered, so an unknown key
    # reports "unknown key" rather than "invalid value".
    for known in "${HYPRX_CONFIG_KEYS[@]}"; do
        if [[ "$known" != "$key" ]]; then
            continue
        fi

        # Validate BEFORE writing. This function used to persist first and leave
        # the caller to validate afterwards, and commands/config.sh then tried to
        # undo the write with hyprx_config_unset - which restores the DEFAULT,
        # not the previous value. So `config set LOG_LEVEL debug` followed by a
        # typo'd `config set LOG_LEVEL verbose` silently reset LOG_LEVEL to
        # info while printing "Current value left unchanged".
        #
        # Validation lives here so every caller gets it, including any future
        # one that is not commands/config.sh.
        if ! hyprx_config_validate "$1" "$2"; then
            return 2
        fi

        printf -v "$key" '%s' "$2"
        hyprx_config_save

        # THEME is the one key with an effect beyond its own value. It used to
        # validate and do nothing, so `hyprx config set THEME one-dark` reported
        # success while the bar kept its default colours - a setting that
        # silently does nothing is worse than no setting.
        #
        # The theme is copied to themes/active.css, which the wallust template
        # imports. It has to be a copy rather than a pointer: wallust regenerates
        # that template on every wallpaper change, and a theme referenced only
        # from the committed default would stop being applied at exactly the
        # moment it matters.
        if [[ "$1" == "THEME" ]]; then
            hyprx_config_apply_theme "$2"
        fi

        return 0
    done

    return 1
}

# Install a theme into the deployed waybar config.
#
# The destination is themes/active.css. An unknown or empty name installs the
# empty default, so `config unset THEME` and `config set THEME ""` both return
# the bar to its default colours rather than leaving a stale theme behind.
hyprx_config_apply_theme() {
    local name="$1"
    local source_dir="${HYPRX_CONFIG:?}/waybar/themes"
    local target_dir="${HYPRX_TARGET_HOME:-$HOME}/.config/waybar/themes"
    local target="$target_dir/active.css"

    mkdir -p "$target_dir" 2>/dev/null || true

    if [[ -z "$name" || "$name" == "default" ]]; then
        cp "$source_dir/active.css" "$target" 2>/dev/null || true
        return 0
    fi

    if [[ ! -f "$source_dir/$name.css" ]]; then
        hyprx_ui_error "No such theme: $name"
        return 1
    fi

    cp "$source_dir/$name.css" "$target"
}

hyprx_config_unset() {
    local key default
    key="$(hyprx_config_key_of "$1")"

    default="$(hyprx_config_default_value "$1")" || return 1

    printf -v "$key" '%s' "$default"
    hyprx_config_save

    # THEME again: unsetting it must put the empty default theme back, or the
    # bar keeps the colours of a theme the config no longer names.
    if [[ "$1" == "THEME" ]]; then
        hyprx_config_apply_theme ""
    fi

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
            # Must name a theme that actually exists.
            #
            # This tested `-d` against config/waybar/themes/$value, but a theme
            # is a .css FILE: `hyprx config set THEME one-dark` - the only theme
            # the repo ships - was rejected while config/hyprx.conf advertised
            # "must exist in config/waybar/themes/". `-e` accepts both a file
            # and a directory, so it works either way; the .css suffix is
            # accepted too so `THEME=one-dark.css` also resolves.
            [[ "$value" == "default" ]] && return 0

            local theme_dir="${HYPRX_CONFIG:?}/waybar/themes"
            [[ -e "$theme_dir/$value" ]] && return 0
            [[ -e "$theme_dir/$value.css" ]] && return 0
            return 1
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
            # A path must be absolute or ~-relative.
            #
            # Surrounding quotes are stripped before the test because the loader
            # strips them: hyprx.conf holds `LOG_FILE="/var/log/my#app.log"` and
            # that has to satisfy the same rule as the bare form. Without this,
            # a value that round-trips correctly through the file was rejected
            # on the command line.
            local path="$value"
            path="${path%\"}"; path="${path#\"}"
            path="${path%\'}"; path="${path#\'}"

            [[ -z "$path" ]] && return 0
            [[ "$path" == /* || "$path" == ~/* ]] || return 1
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

# Machine-readable twin of `config list` for the GUI settings screen.
hyprx_config_list_json() {
    local k first=1
    printf '{'
    for k in "${HYPRX_CONFIG_KEYS[@]}"; do
        (( first == 0 )) && printf ','
        first=0
        printf '"%s":"%s"' "${k#HYPRX_CONFIG_}" "$(hyprx_event_escape "${!k}")"
    done
    printf '}\n'
}

# Boolean value of a config key, by variable name.
hyprx_config_bool() {
    [[ "${!1}" == "true" ]]
}

# Reads the file back from disk and describes what KEY is actually set to
# there. Used by `config set` after a rejection to state - rather than imply -
# that nothing was written.
hyprx_config_current_is() {
    local key value
    key="$(hyprx_config_key_of "$1")"

    if ! hyprx_config_get "$1" >/dev/null 2>&1; then
        printf 'Unknown key.'
        return 0
    fi

    value="${!key}"
    printf 'Currently: %s=%s' "${key#HYPRX_CONFIG_}" "$value"
}

hyprx_config_load
