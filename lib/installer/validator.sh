#!/usr/bin/env bash

validate_packages() {

    header
    info "Validating packages..."

    VALIDATED_QUEUE=()
    INVALID_PACKAGES=()
    REPLACED_PACKAGES=()

    declare -A seen

    for pkg in "${PACKAGE_QUEUE[@]}"; do

        ########################################
        # Forced replacements
        ########################################

        replacement="$(get_replacement "$pkg")"

        if [[ -n "$replacement" ]]; then

            warn "$pkg → $replacement"

            REPLACED_PACKAGES+=("$pkg -> $replacement")

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

        if package_exists_official "$pkg"; then

            VALIDATED_QUEUE+=("$pkg")

            continue

        fi

        ########################################
        # AUR
        ########################################

        if package_exists_aur "$pkg"; then

            VALIDATED_QUEUE+=("$pkg")

            continue

        fi

        ########################################
        # Invalid package
        ########################################

        error "Package not found: $pkg"

        INVALID_PACKAGES+=("$pkg")

    done

    PACKAGE_QUEUE=("${VALIDATED_QUEUE[@]}")

    divider

    success "Validation complete."

    echo

    printf "%-20s %d\n" "Valid" "${#PACKAGE_QUEUE[@]}"
    printf "%-20s %d\n" "Replaced" "${#REPLACED_PACKAGES[@]}"
    printf "%-20s %d\n" "Invalid" "${#INVALID_PACKAGES[@]}"

    echo

    if (( ${#INVALID_PACKAGES[@]} > 0 )); then

        warn "Invalid packages"

        for pkg in "${INVALID_PACKAGES[@]}"; do
            echo " • $pkg"
        done

        echo

    fi

}