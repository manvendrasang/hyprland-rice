#!/usr/bin/env bash

hyprx_validator_validate() {

    hyprx_ui_header
    hyprx_ui_info "Validating packages..."

    HYPRX_VALIDATED_QUEUE=()
    HYPRX_INVALID_PACKAGES=()
    HYPRX_REPLACED_PACKAGES=()

    declare -A seen

    for pkg in "${HYPRX_INSTALL_QUEUE[@]}"; do

        ########################################
        # Validate package name format
        ########################################

        if ! hyprx_util_validate_package_name "$pkg"; then
            hyprx_ui_error "Invalid package name: $pkg"
            HYPRX_INVALID_PACKAGES+=("$pkg")
            continue
        fi

        ########################################
        # Forced replacements
        ########################################

        replacement="$(hyprx_replacements_get "$pkg")"

        if [[ -n "$replacement" ]]; then

            hyprx_ui_warn "$pkg → $replacement"

            HYPRX_REPLACED_PACKAGES+=("$pkg -> $replacement")

            pkg="$replacement"

        fi

        ########################################
        # Skip duplicates
        ########################################

        [[ -n "${seen[$pkg]:-}" ]] && continue

        seen["$pkg"]=1

        ########################################
        # Official repository
        ########################################

        if hyprx_pkg_exists_official "$pkg"; then

            HYPRX_VALIDATED_QUEUE+=("$pkg")

            continue

        fi

        ########################################
        # AUR
        ########################################

        if hyprx_pkg_exists_aur "$pkg"; then

            HYPRX_VALIDATED_QUEUE+=("$pkg")

            continue

        fi

        ########################################
        # Invalid package
        ########################################

        hyprx_ui_error "Package not found: $pkg"

        local hint
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

    fi

}
