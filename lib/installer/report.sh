#!/usr/bin/env bash

generate_report() {

    REPORT="$HOME/Desktop/HyprX-Install-Report.txt"

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

        echo "Host:"
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
        echo "$PACKAGE_MANAGER"
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

        echo "Installed Packages"
        echo "------------------"

        if (( ${#INSTALLED_PACKAGES[@]} > 0 )); then

            for pkg in "${INSTALLED_PACKAGES[@]}"; do
                echo "✓ $pkg"
            done

        else

            echo "None"

        fi

        echo

        echo "Skipped Packages"
        echo "----------------"

        if (( ${#SKIPPED_PACKAGES[@]} > 0 )); then

            for pkg in "${SKIPPED_PACKAGES[@]}"; do
                echo "• $pkg"
            done

        else

            echo "None"

        fi

        echo

        echo "Failed Packages"
        echo "---------------"

        if (( ${#FAILED_PACKAGES[@]} > 0 )); then

            for pkg in "${FAILED_PACKAGES[@]}"; do
                echo "✗ $pkg"
            done

        else

            echo "None"

        fi

        echo

        echo "Replaced Packages"
        echo "-----------------"

        if (( ${#REPLACED_PACKAGES[@]} > 0 )); then

            for pkg in "${REPLACED_PACKAGES[@]}"; do
                echo "→ $pkg"
            done

        else

            echo "None"

        fi

        echo

        echo "Invalid Packages"
        echo "----------------"

        if (( ${#INVALID_PACKAGES[@]} > 0 )); then

            for pkg in "${INVALID_PACKAGES[@]}"; do
                echo "✗ $pkg"
            done

        else

            echo "None"

        fi

        echo

        echo "=========================================================="

    } > "$REPORT"

    success "Report written:"
    echo "  $REPORT"

}