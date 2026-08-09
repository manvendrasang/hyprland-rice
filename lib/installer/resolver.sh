#!/usr/bin/env bash

resolve_packages() {

    PACKAGE_QUEUE=()

    local file="$ROOT_DIR/packages.list"
    local pkg

    if [[ -f "$file" ]]; then

        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            PACKAGE_QUEUE+=("$pkg")
        done <"$file"

    fi

    mapfile -t PACKAGE_QUEUE < <(
        printf "%s\n" "${PACKAGE_QUEUE[@]}" | sort -u
    )

}
