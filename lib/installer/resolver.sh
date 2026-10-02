#!/usr/bin/env bash

hyprx_resolver_resolve() {
    HYPRX_INSTALL_QUEUE=()

    local file="$HYPRX_ROOT/packages.list"
    local pkg

    if [[ -f "$file" ]]; then
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            HYPRX_INSTALL_QUEUE+=("$pkg")
        done <"$file"
    fi

    mapfile -t HYPRX_INSTALL_QUEUE < <(
        printf "%s\n" "${HYPRX_INSTALL_QUEUE[@]}" | sort -u
    )
}
