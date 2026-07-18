#!/usr/bin/env bash

resolve_packages() {

    PACKAGE_QUEUE=()

    local module
    local file
    local pkg

    for module in "${SELECTED_MODULES[@]}"; do

        file="$ROOT_DIR/modules/$module/packages.list"

        [[ -f "$file" ]] || continue

        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            PACKAGE_QUEUE+=("$pkg")
        done <"$file"

    done

    mapfile -t PACKAGE_QUEUE < <(
        printf "%s\n" "${PACKAGE_QUEUE[@]}" | sort -u
    )

}