#!/usr/bin/env bash

declare -gA HYPRX_REQUIREMENTS

# database/package-requirements.conf maps a package to a hint shown when it
# cannot be found (e.g. steam -> "requires [multilib]").
hyprx_requirements_load() {
    HYPRX_REQUIREMENTS=()

    local db="$HYPRX_ROOT/database/package-requirements.conf"
    [[ -f "$db" ]] || return 0

    local line pkg hint

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        IFS="=" read -r pkg hint <<<"$line"

        pkg="$(echo "$pkg" | xargs)"
        hint="$(echo "$hint" | xargs)"

        [[ -z "$pkg" ]] && continue
        [[ -z "$hint" ]] && continue

        HYPRX_REQUIREMENTS["$pkg"]="$hint"
    done <"$db"
}

hyprx_requirements_get_hint() {
    echo "${HYPRX_REQUIREMENTS[$1]:-}"
}

hyprx_requirements_load
