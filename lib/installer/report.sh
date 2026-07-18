#!/usr/bin/env bash

generate_report() {

    local report="$HOME/Desktop/HyprX-Install-Report.txt"
    local now
    local duration_minutes
    local duration_seconds

    now="$(date)"

    duration_minutes=$((INSTALL_DURATION / 60))
    duration_seconds=$((INSTALL_DURATION % 60))

    {
        echo "=========================================================="
        echo "                 HyprX Installation Report"
        echo "=========================================================="
        echo

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
        echo "${PACKAGE_MANAGER:-Unknown}"
        echo

        echo "Installation Time"
        echo "-----------------"
        printf "%02d minutes %02d seconds\n" \
            "$duration_minutes" \
            "$duration_seconds"
        echo

        echo "Selected Modules"
        echo "----------------"

        if (( ${#SELECTED_MODULES[@]} > 0 )); then
            for module in "${SELECTED_MODULES[@]}"; do
                echo "• $module"
            done
        else
            echo "None"
        fi

        echo

        echo "Statistics"
        echo "----------"

        printf "Installed : %d\n" "${#INSTALLED_PACKAGES[@]}"
        printf "Skipped   : %d\n" "${#SKIPPED_PACKAGES[@]}"
        printf "Failed    : %d\n" "${#FAILED_PACKAGES[@]}"
        printf "Invalid   : %d\n" "${#INVALID_PACKAGES[@]}"
        printf "Replaced  : %d\n" "${#REPLACED_PACKAGES[@]}"

        echo

        for section in \
            "Installed Packages:✓:${INSTALLED_PACKAGES[*]}" \
            "Skipped Packages:•:${SKIPPED_PACKAGES[*]}" \
            "Failed Packages:✗:${FAILED_PACKAGES[*]}" \
            "Replaced Packages:→:${REPLACED_PACKAGES[*]}" \
            "Invalid Packages:✗:${INVALID_PACKAGES[*]}"; do

            IFS=: read -r title symbol _ <<<"$section"

            echo "$title"
            printf '%*s\n' "${#title}" '' | tr ' ' '-'

            case "$title" in
                "Installed Packages") arr=("${INSTALLED_PACKAGES[@]}") ;;
                "Skipped Packages") arr=("${SKIPPED_PACKAGES[@]}") ;;
                "Failed Packages") arr=("${FAILED_PACKAGES[@]}") ;;
                "Replaced Packages") arr=("${REPLACED_PACKAGES[@]}") ;;
                "Invalid Packages") arr=("${INVALID_PACKAGES[@]}") ;;
            esac

            if (( ${#arr[@]} > 0 )); then
                for item in "${arr[@]}"; do
                    echo "$symbol $item"
                done
            else
                echo "None"
            fi

            echo
        done

        echo "=========================================================="

    } >"$report"

    success "Report written:"
    echo "  $report"

}