#!/usr/bin/env bash

declare -gA PACKAGE_REQUIREMENTS

load_requirements() {

    PACKAGE_REQUIREMENTS=()

    local db="$ROOT_DIR/database/package-requirements.conf"

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

        PACKAGE_REQUIREMENTS["$pkg"]="$hint"

    done < "$db"

}

get_requirement_hint() {

    local pkg="$1"

    echo "${PACKAGE_REQUIREMENTS[$pkg]:-}"

}

load_requirements
