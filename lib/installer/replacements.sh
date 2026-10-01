#!/usr/bin/env bash

declare -gA HYPRX_REPLACEMENTS
declare -gA HYPRX_REPLACEMENT_MODE

hyprx_replacements_load() {

    HYPRX_REPLACEMENTS=()
    HYPRX_REPLACEMENT_MODE=()

    local db="$HYPRX_ROOT/database/package-replacements.conf"

    [[ -f "$db" ]] || return 0

    while IFS= read -r line; do

        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        local old
        local new
        local mode

        if [[ "$line" == *"|"* ]]; then

            IFS="|" read -r old new mode <<< "$line"

        else

            IFS="=" read -r old new <<< "$line"

            mode="forced"

        fi

        old="$(echo "$old" | xargs)"
        new="$(echo "$new" | xargs)"
        mode="$(echo "$mode" | xargs)"

        [[ -z "$old" ]] && continue
        [[ -z "$new" ]] && continue

        HYPRX_REPLACEMENTS["$old"]="$new"
        HYPRX_REPLACEMENT_MODE["$old"]="$mode"

    done < "$db"

}

hyprx_replacements_get() {

    local pkg="$1"

    echo "${HYPRX_REPLACEMENTS[$pkg]:-}"

}

hyprx_replacements_get_mode() {

    local pkg="$1"

    echo "${HYPRX_REPLACEMENT_MODE[$pkg]:-forced}"

}

hyprx_replacements_print() {

    hyprx_ui_divider

    hyprx_ui_info "Package Replacement Database"

    printf "%-30s %-30s %-10s\n" \
        "Original" \
        "Replacement" \
        "Mode"

    hyprx_ui_divider

    for pkg in "${!HYPRX_REPLACEMENTS[@]}"; do

        printf "%-30s %-30s %-10s\n" \
            "$pkg" \
            "${HYPRX_REPLACEMENTS[$pkg]}" \
            "${HYPRX_REPLACEMENT_MODE[$pkg]}"

    done

}

hyprx_replacements_load
