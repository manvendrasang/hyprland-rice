#!/usr/bin/env bash

declare -gA HYPRX_REPLACEMENTS

# The database's optional third column (old|new|mode) is parsed for format
# compatibility and discarded - every replacement is applied as forced.
hyprx_replacements_load() {
    HYPRX_REPLACEMENTS=()

    local db="$HYPRX_ROOT/database/package-replacements.conf"
    [[ -f "$db" ]] || return 0

    local line old new mode

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        if [[ "$line" == *"|"* ]]; then
            IFS="|" read -r old new mode <<< "$line"
        else
            IFS="=" read -r old new <<< "$line"
        fi

        old="$(echo "$old" | xargs)"
        new="$(echo "$new" | xargs)"

        [[ -z "$old" ]] && continue
        [[ -z "$new" ]] && continue

        HYPRX_REPLACEMENTS["$old"]="$new"
    done <"$db"
}

hyprx_replacements_get() {
    echo "${HYPRX_REPLACEMENTS[$1]:-}"
}

hyprx_replacements_load
