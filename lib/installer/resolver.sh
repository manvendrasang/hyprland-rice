#!/usr/bin/env bash

hyprx_resolver_resolve() {
    HYPRX_INSTALL_QUEUE=()

    local file="$HYPRX_ROOT/packages.list"
    local pkg

    # Explicitly able to fail. engine.sh calls this as
    # `hyprx_resolver_resolve || return 1`, and a guard on something that cannot
    # return 1 is not a guard: the function used to end on `mapfile`, which
    # exits 0 whatever happened, so a missing or unreadable packages.list
    # produced an empty queue and the install went on to report
    # "All packages installed successfully" with Installed 0 - the same false
    # success the validator's dead guard used to tell.
    #
    # The emptiness check sits BEFORE the mapfile on purpose. With an empty
    # array, `printf "%s\n" "${HYPRX_INSTALL_QUEUE[@]}"` emits one empty line,
    # sort -u keeps it, and the queue comes back holding a single empty string -
    # so a check placed afterwards would see length 1 and wave a blank
    # packages.list through.
    if [[ ! -f "$file" ]]; then
        hyprx_ui_error "packages.list not found: $file"
        hyprx_ui_info "This is a broken checkout, not an empty install."
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        hyprx_ui_error "packages.list is not readable: $file"
        return 1
    fi

    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        HYPRX_INSTALL_QUEUE+=("$pkg")
    done <"$file"

    if (( ${#HYPRX_INSTALL_QUEUE[@]} == 0 )); then
        hyprx_ui_error "packages.list declares no packages - nothing to install"
        hyprx_ui_info "Every entry is commented out, or the file is empty."
        return 1
    fi

    mapfile -t HYPRX_INSTALL_QUEUE < <(
        printf "%s\n" "${HYPRX_INSTALL_QUEUE[@]}" | sort -u
    )

    return 0
}