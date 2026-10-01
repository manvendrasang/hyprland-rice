#!/usr/bin/env bash

# Overridable for test isolation - see the note in lib/logger.sh. Without
# this, a run that exercises the recovery path rewrites the real
# ~/.local/state/hyprx/install.state, which the next real install would then
# try to "resume" from.
HYPRX_RECOVERY_STATE_DIR="${HYPRX_RECOVERY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}"
HYPRX_RECOVERY_STATE_FILE="$HYPRX_RECOVERY_STATE_DIR/install.state"

mkdir -p "$HYPRX_RECOVERY_STATE_DIR"

########################################
# Save current installation state
########################################

hyprx_recovery_save_state() {

    # A dry run never installs anything, so it must not leave a pending
    # queue behind - the next real run would try to "resume" a phantom
    # interrupted install.
    hyprx_util_dry_run && return 0

    {
        echo "PACKAGE_MANAGER=$HYPRX_DETECT_PACKAGE_MANAGER"

        echo

        echo "[PENDING]"

        for pkg in "${HYPRX_INSTALL_QUEUE[@]}"; do
            echo "$pkg"
        done

    } > "$HYPRX_RECOVERY_STATE_FILE"

}

########################################
# Resume installation
########################################

hyprx_recovery_resume() {

    [[ -f "$HYPRX_RECOVERY_STATE_FILE" ]] || return 1

    HYPRX_INSTALL_QUEUE=()

    local section=""

    while IFS= read -r line; do

        [[ -z "$line" ]] && continue

        case "$line" in

            PACKAGE_MANAGER=*)

                HYPRX_DETECT_PACKAGE_MANAGER="${line#*=}"
                ;;

            "[PENDING]")

                section="packages"
                ;;

            *)

                case "$section" in

                    packages)

                        HYPRX_INSTALL_QUEUE+=("$line")
                        ;;

                esac
                ;;

        esac

    done < "$HYPRX_RECOVERY_STATE_FILE"

    if (( ${#HYPRX_INSTALL_QUEUE[@]} == 0 )); then
        return 1
    fi

    hyprx_ui_success "Recovered interrupted installation."

    hyprx_ui_info "Remaining packages: ${#HYPRX_INSTALL_QUEUE[@]}"

    return 0

}

########################################
# Remove completed package
########################################

hyprx_recovery_mark_complete() {

    local pkg="$1"

    [[ -f "$HYPRX_RECOVERY_STATE_FILE" ]] || return 0

    HYPRX_INSTALL_QUEUE=()

    hyprx_recovery_resume >/dev/null 2>&1 || return 0

    local remaining=()

    for item in "${HYPRX_INSTALL_QUEUE[@]}"; do

        [[ "$item" == "$pkg" ]] && continue

        remaining+=("$item")

    done

    HYPRX_INSTALL_QUEUE=("${remaining[@]}")

    hyprx_recovery_save_state

}

########################################
# Delete state
########################################

hyprx_recovery_clear_state() {

    hyprx_util_dry_run && return 0

    rm -f "$HYPRX_RECOVERY_STATE_FILE"

}

########################################
# Installation interrupted?
########################################

hyprx_recovery_has_state() {

    [[ -f "$HYPRX_RECOVERY_STATE_FILE" ]]

}
