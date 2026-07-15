#!/usr/bin/env bash

MAX_RETRIES=3
RETRY_BASE_DELAY=2

retry_failed_packages() {

    [[ ${#FAILED_PACKAGES[@]} -eq 0 ]] && return 0

    local remaining=("${FAILED_PACKAGES[@]}")

    FAILED_PACKAGES=()

    local attempt
    local delay

    for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do

        [[ ${#remaining[@]} -eq 0 ]] && break

        divider

        info "Retry attempt $attempt/$MAX_RETRIES"

        local current_failed=()

        for pkg in "${remaining[@]}"; do

            info "Retrying $pkg"

            install_package "$pkg"
            status=$?

            case "$status" in

                0)

                    success "$pkg"

                    INSTALLED_PACKAGES+=("$pkg")

                    mark_package_complete "$pkg"

                    ;;

                10)

                    info "$pkg already installed."

                    SKIPPED_PACKAGES+=("$pkg")

                    mark_package_complete "$pkg"

                    ;;

                *)

                    warn "$pkg failed again"

                    current_failed+=("$pkg")

                    log_failed_package \
                        "$pkg" \
                        "Retry $attempt failed"

                    ;;

            esac

        done

        remaining=("${current_failed[@]}")

        if (( ${#remaining[@]} == 0 )); then
            break
        fi

        if (( attempt < MAX_RETRIES )); then

            delay=$((RETRY_BASE_DELAY ** attempt))

            warn "Waiting ${delay}s before next retry..."

            sleep "$delay"

        fi

    done

    FAILED_PACKAGES=("${remaining[@]}")

    if (( ${#FAILED_PACKAGES[@]} == 0 )); then

        success "All failed packages recovered."

    else

        warn "Some packages could not be installed."

    fi

}