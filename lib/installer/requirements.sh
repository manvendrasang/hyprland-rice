#!/usr/bin/env bash

declare -gA HYPRX_REQUIREMENTS

hyprx_requirements_load() {

    HYPRX_REQUIREMENTS=()

    local db="$HYPRX_ROOT/database/package-requirements.conf"

    [[ -f "$db" ]] || return 0

    while IFS= read -r line; do

        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        local pkg
        local hint

        IFS="=" read -r pkg hint <<< "$line"

        pkg="$(echo "$pkg" | xargs)"
        hint="$(echo "$hint" | xargs)"

        [[ -z "$pkg" ]] && continue
        [[ -z "$hint" ]] && continue

        HYPRX_REQUIREMENTS["$pkg"]="$hint"

    done < "$db"

}

hyprx_requirements_get_hint() {

    local pkg="$1"

    echo "${HYPRX_REQUIREMENTS[$pkg]:-}"

}

hyprx_requirements_load
