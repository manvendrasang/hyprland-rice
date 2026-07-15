#!/usr/bin/env bash

STATE_DIR="$HOME/.local/state/hyprx"
STATE_FILE="$STATE_DIR/install.state"

mkdir -p "$STATE_DIR"

########################################
# Save current installation state
########################################

save_install_state() {

    {
        echo "PACKAGE_MANAGER=$PACKAGE_MANAGER"

        echo

        echo "[MODULES]"

        for module in "${SELECTED_MODULES[@]}"; do
            echo "$module"
        done

        echo

        echo "[PENDING]"

        for pkg in "${PACKAGE_QUEUE[@]}"; do
            echo "$pkg"
        done

    } > "$STATE_FILE"

}

########################################
# Resume installation
########################################

resume_install() {

    [[ -f "$STATE_FILE" ]] || return 1

    PACKAGE_QUEUE=()
    SELECTED_MODULES=()

    local section=""

    while IFS= read -r line; do

        [[ -z "$line" ]] && continue

        case "$line" in

            PACKAGE_MANAGER=*)

                PACKAGE_MANAGER="${line#*=}"
                ;;

            "[MODULES]")

                section="modules"
                ;;

            "[PENDING]")

                section="packages"
                ;;

            *)

                case "$section" in

                    modules)

                        SELECTED_MODULES+=("$line")
                        ;;

                    packages)

                        PACKAGE_QUEUE+=("$line")
                        ;;

                esac
                ;;

        esac

    done < "$STATE_FILE"

    if (( ${#PACKAGE_QUEUE[@]} == 0 )); then
        return 1
    fi

    success "Recovered interrupted installation."

    info "Remaining packages: ${#PACKAGE_QUEUE[@]}"

    return 0

}

########################################
# Remove completed package
########################################

mark_package_complete() {

    local pkg="$1"

    [[ -f "$STATE_FILE" ]] || return 0

    PACKAGE_QUEUE=()

    resume_install >/dev/null 2>&1 || return 0

    local remaining=()

    for item in "${PACKAGE_QUEUE[@]}"; do

        [[ "$item" == "$pkg" ]] && continue

        remaining+=("$item")

    done

    PACKAGE_QUEUE=("${remaining[@]}")

    save_install_state

}

########################################
# Delete state
########################################

clear_install_state() {

    rm -f "$STATE_FILE"

}

########################################
# Show pending packages
########################################

show_pending_packages() {

    [[ -f "$STATE_FILE" ]] || return 1

    resume_install >/dev/null 2>&1 || return 1

    printf "%s\n" "${PACKAGE_QUEUE[@]}"

}

########################################
# Installation interrupted?
########################################

has_install_state() {

    [[ -f "$STATE_FILE" ]]

}