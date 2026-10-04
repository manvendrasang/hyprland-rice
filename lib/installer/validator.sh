#!/usr/bin/env bash

hyprx_validator_validate() {
    # No hyprx_ui_header here. The engine opens with one banner for the whole
    # run; four stages each printing their own meant a single install scrolled
    # past five copies of the same box. Use hyprx_ui_section to label the stage.
    hyprx_ui_section "Validating packages"

    HYPRX_VALIDATED_QUEUE=()
    HYPRX_INVALID_PACKAGES=()
    HYPRX_REPLACED_PACKAGES=()

    local pkg replacement hint
    declare -A seen

    for pkg in "${HYPRX_INSTALL_QUEUE[@]}"; do

        if ! hyprx_util_validate_package_name "$pkg"; then
            hyprx_ui_error "Invalid package name: $pkg"
            HYPRX_INVALID_PACKAGES+=("$pkg")
            continue
        fi

        replacement="$(hyprx_replacements_get "$pkg")"
        if [[ -n "$replacement" ]]; then
            hyprx_ui_warn "$pkg → $replacement"
            HYPRX_REPLACED_PACKAGES+=("$pkg -> $replacement")
            pkg="$replacement"
        fi

        # Two original names can replace to the same package.
        [[ -n "${seen[$pkg]:-}" ]] && continue
        seen["$pkg"]=1

        if hyprx_pkg_exists_official "$pkg" || hyprx_pkg_exists_aur "$pkg"; then
            HYPRX_VALIDATED_QUEUE+=("$pkg")
            continue
        fi

        hyprx_ui_error "Package not found: $pkg"

        hint="$(hyprx_requirements_get_hint "$pkg")"
        [[ -n "$hint" ]] && hyprx_ui_warn "  → $hint"

        HYPRX_INVALID_PACKAGES+=("$pkg")
    done

    HYPRX_INSTALL_QUEUE=("${HYPRX_VALIDATED_QUEUE[@]}")

    hyprx_ui_divider
    hyprx_ui_success "Validation complete."
    echo

    printf "%-20s %d\n" "Valid" "${#HYPRX_INSTALL_QUEUE[@]}"
    printf "%-20s %d\n" "Replaced" "${#HYPRX_REPLACED_PACKAGES[@]}"
    printf "%-20s %d\n" "Invalid" "${#HYPRX_INVALID_PACKAGES[@]}"
    echo

    if (( ${#HYPRX_INVALID_PACKAGES[@]} > 0 )); then
        hyprx_ui_warn "Invalid packages"
        for pkg in "${HYPRX_INVALID_PACKAGES[@]}"; do
            echo " • $pkg"
        done
        echo

        # An EXPLICIT return. This block used to be the function's last
        # statement, and `if cond; then ...; fi` exits 0 whether the body ran
        # or not - so `hyprx_validator_validate || return 1` in engine.sh was
        # dead code. A real install whose queue named something that does not
        # exist printed "Package not found: bad", then deployed every config,
        # installed the fonts, snapshotted, wrote a report and exited 0 with
        # "Installation completed successfully."
        #
        # Returning 1 does not make the caller abort: engine.sh records it and
        # keeps going, because the configs and the snapshot are exactly what
        # someone with a broken package list needs in order to recover. It only
        # changes the final message and the exit code, which is the part that
        # was lying.
        return 1
    fi

    return 0
}
