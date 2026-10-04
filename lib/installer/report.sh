#!/usr/bin/env bash

hyprx_report_generate() {
    local report="$HYPRX_STATE_REPORT_FILE"
    local now duration_minutes duration_seconds

    mkdir -p "$(dirname "$report")"

    # The report must render even if a stage never populated its array.
    local _arr
    for _arr in HYPRX_INSTALL_INSTALLED HYPRX_INSTALL_SKIPPED HYPRX_INSTALL_FAILED \
                 HYPRX_INVALID_PACKAGES HYPRX_REPLACED_PACKAGES; do
        declare -p "$_arr" &>/dev/null || eval "$_arr=()"
    done

    now="$(date)"

    duration_minutes=$(( ${HYPRX_INSTALL_DURATION:-0} / 60 ))
    duration_seconds=$(( ${HYPRX_INSTALL_DURATION:-0} % 60 ))

    {
        echo "=========================================================="
        echo "                 HyprX Installation Report"
        echo "=========================================================="
        echo

        if hyprx_util_dry_run; then
            echo "!! DRY RUN - this report describes what WOULD happen."
            echo "!! No packages were installed and no configs were deployed."
            echo
        fi

        echo "Date"
        echo "----"
        echo "$now"
        echo

        echo "Host"
        echo "----"
        uname -n
        echo

        echo "Operating System"
        echo "----------------"
        grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"'
        echo

        echo "Kernel"
        echo "------"
        uname -r
        echo

        echo "Session"
        echo "-------"
        echo "${XDG_SESSION_TYPE:-Unknown}"
        echo

        echo "Package Manager"
        echo "---------------"
        echo "${HYPRX_DETECT_PACKAGE_MANAGER:-Unknown}"
        echo

        echo "Installation Time"
        echo "-----------------"
        printf "%02d minutes %02d seconds\n" \
            "$duration_minutes" \
            "$duration_seconds"
        echo

        echo "Statistics"
        echo "----------"

        printf "Installed : %d\n" "${#HYPRX_INSTALL_INSTALLED[@]}"
        printf "Skipped   : %d\n" "${#HYPRX_INSTALL_SKIPPED[@]}"
        printf "Failed    : %d\n" "${#HYPRX_INSTALL_FAILED[@]}"
        printf "Invalid   : %d\n" "${#HYPRX_INVALID_PACKAGES[@]}"
        printf "Replaced  : %d\n" "${#HYPRX_REPLACED_PACKAGES[@]}"

        echo

        local -a titles=(
            "Installed Packages"
            "Skipped Packages"
            "Failed Packages"
            "Replaced Packages"
            "Invalid Packages"
        )
        local -a symbols=("✓" "•" "✗" "→" "✗")
        local i title symbol arr_name item hint

        for i in "${!titles[@]}"; do
            title="${titles[$i]}"
            symbol="${symbols[$i]}"

            case "$i" in
                0) arr_name=HYPRX_INSTALL_INSTALLED ;;
                1) arr_name=HYPRX_INSTALL_SKIPPED ;;
                2) arr_name=HYPRX_INSTALL_FAILED ;;
                3) arr_name=HYPRX_REPLACED_PACKAGES ;;
                4) arr_name=HYPRX_INVALID_PACKAGES ;;
            esac

            echo "$title"
            printf '%*s\n' "${#title}" '' | tr ' ' '-'

            # Nameref, not string indirection: ${!arr_name[@]} on a scalar
            # holding an array name yields nothing useful.
            local -n arr="$arr_name"

            if (( ${#arr[@]} == 0 )); then
                echo "None"
            else
                for item in "${arr[@]}"; do
                    # Invalid packages get their database hint appended.
                    hint=""
                    [[ "$title" == "Invalid Packages" ]] && hint="$(hyprx_requirements_get_hint "$item")"

                    if [[ -n "$hint" ]]; then
                        echo "$symbol $item — $hint"
                    else
                        echo "$symbol $item"
                    fi
                done
            fi

            unset -n arr
            echo
        done

        echo "=========================================================="

    } >"$report" || {
        # engine.sh calls this as `hyprx_report_generate || return 1`, and that
        # guard was dead: a failed redirection was followed by an unconditional
        # hyprx_ui_success "Report written:", so an unwritable report path
        # announced success and the run finished claiming everything was fine -
        # while the file the user was told to look at did not exist.
        hyprx_ui_error "Could not write the install report to $report"
        hyprx_ui_info "Everything else in the run completed; only the report is missing."
        return 1
    }

    hyprx_ui_success "Report written:"
    echo "  $report"

    return 0
}
