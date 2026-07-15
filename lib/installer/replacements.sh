#!/usr/bin/env bash

declare -gA PACKAGE_REPLACEMENTS
declare -gA REPLACEMENT_MODE

load_replacements() {

    PACKAGE_REPLACEMENTS=()
    REPLACEMENT_MODE=()

    local db="$ROOT_DIR/database/package-replacements.conf"

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

        PACKAGE_REPLACEMENTS["$old"]="$new"
        REPLACEMENT_MODE["$old"]="$mode"

    done < "$db"

}

get_replacement() {

    local pkg="$1"

    echo "${PACKAGE_REPLACEMENTS[$pkg]:-}"

}

get_replacement_mode() {

    local pkg="$1"

    echo "${REPLACEMENT_MODE[$pkg]:-forced}"

}

print_replacements() {

    divider

    info "Package Replacement Database"

    printf "%-30s %-30s %-10s\n" \
        "Original" \
        "Replacement" \
        "Mode"

    divider

    for pkg in "${!PACKAGE_REPLACEMENTS[@]}"; do

        printf "%-30s %-30s %-10s\n" \
            "$pkg" \
            "${PACKAGE_REPLACEMENTS[$pkg]}" \
            "${REPLACEMENT_MODE[$pkg]}"

    done

}

load_replacements