#!/usr/bin/env bash

hyprx_report_generate() {

    local report="${HYPRX_REPORT_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/HyprX-Install-Report.txt}"
    local now
    local duration_minutes
    local duration_seconds

    mkdir -p "$(dirname "$report")"

    for _arr in HYPRX_INSTALL_INSTALLED HYPRX_INSTALL_SKIPPED HYPRX_INSTALL_FAILED HYPRX_INVALID_PACKAGES HYPRX_REPLACED_PACKAGES; do
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

        for section in \
            "Installed Packages:✓:${HYPRX_INSTALL_INSTALLED[*]}" \
            "Skipped Packages:•:${HYPRX_INSTALL_SKIPPED[*]}" \
            "Failed Packages:✗:${HYPRX_INSTALL_FAILED[*]}" \
            "Replaced Packages:→:${HYPRX_REPLACED_PACKAGES[*]}" \
            "Invalid Packages:✗:${HYPRX_INVALID_PACKAGES[*]}"; do

            IFS=: read -r title symbol _ <<<"$section"

            echo "$title"
            printf '%*s\n' "${#title}" '' | tr ' ' '-'

            case "$title" in
                "Installed Packages") arr=("${HYPRX_INSTALL_INSTALLED[@]}") ;;
                "Skipped Packages") arr=("${HYPRX_INSTALL_SKIPPED[@]}") ;;
                "Failed Packages") arr=("${HYPRX_INSTALL_FAILED[@]}") ;;
                "Replaced Packages") arr=("${HYPRX_REPLACED_PACKAGES[@]}") ;;
                "Invalid Packages") arr=("${HYPRX_INVALID_PACKAGES[@]}") ;;
            esac

            if (( ${#arr[@]} > 0 )); then
                for item in "${arr[@]}"; do
                    if [[ "$title" == "Invalid Packages" ]]; then
                        local hint
                        hint="$(hyprx_requirements_get_hint "$item")"
                        if [[ -n "$hint" ]]; then
                            echo "$symbol $item — $hint"
                        else
                            echo "$symbol $item"
                        fi
                    else
                        echo "$symbol $item"
                    fi
                done
            else
                echo "None"
            fi

            echo
        done

        echo "=========================================================="

    } >"$report"

    hyprx_ui_success "Report written:"
    echo "  $report"

}
