#!/usr/bin/env bash

ACTION="${1:-help}"

case "$ACTION" in

    list)

        discover_profiles

        section "Available Profiles"

        printf "%s\n" "${AVAILABLE_PROFILES[@]}"

        ;;

    current)

        section "Current Profile"

        current_profile

        ;;

    use)

        PROFILE_NAME="${2:-}"

        [[ -z "$PROFILE_NAME" ]] && {
            error "Usage: hyprx profile use <profile>"
            exit 1
        }

        profile_exists "$PROFILE_NAME" || {
            error "Unknown profile: $PROFILE_NAME"
            exit 1
        }

        set_config PROFILE "$PROFILE_NAME"
        load_config

        success "Active profile: $PROFILE"

        ;;

    show)

        PROFILE_NAME="${2:-}"

        [[ -z "$PROFILE_NAME" ]] && {
            error "Usage: hyprx profile show <profile>"
            exit 1
        }

        profile_exists "$PROFILE_NAME" || {
            error "Unknown profile: $PROFILE_NAME"
            exit 1
        }

        section "Profile Information"

        print_profile "$PROFILE_NAME"

        echo
        info "Modules"

        profile_modules "$PROFILE_NAME"

        ;;

    create)

        PROFILE_ID="${2:-}"

        if [[ -z "$PROFILE_ID" ]]; then
            error "Usage: hyprx profile create <id> [--name NAME] [--description DESC] [--modules mod1,mod2]"
            exit 1
        fi

        if profile_exists "$PROFILE_ID"; then
            error "Profile already exists: $PROFILE_ID"
            exit 1
        fi

        shift 2

        NAME=""
        DESCRIPTION=""
        MODULES_ARG=""

        while (( $# > 0 )); do
            case "$1" in
                --name)
                    NAME="${2:-}"
                    shift 2
                    ;;
                --description)
                    DESCRIPTION="${2:-}"
                    shift 2
                    ;;
                --modules)
                    MODULES_ARG="${2:-}"
                    shift 2
                    ;;
                *)
                    error "Unknown option: $1"
                    exit 1
                    ;;
            esac
        done

        section "Create Profile: $PROFILE_ID"

        if [[ -z "$NAME" ]]; then
            read -rp "Display name [$PROFILE_ID]: " NAME
            NAME="${NAME:-$PROFILE_ID}"
        fi

        if [[ -z "$DESCRIPTION" ]]; then
            read -rp "Description: " DESCRIPTION
        fi

        NEW_MODULES=()

        if [[ -n "$MODULES_ARG" ]]; then

            IFS=',' read -ra NEW_MODULES <<< "$MODULES_ARG"

        else

            discover_modules

            echo
            info "Available modules:"

            MODULE_INDEX=1

            for m in "${AVAILABLE_MODULES[@]}"; do
                printf "  %d) %s\n" "$MODULE_INDEX" "$m"
                MODULE_INDEX=$((MODULE_INDEX + 1))
            done

            echo

            read -rp "Select modules (comma-separated numbers or names): " SELECTION

            IFS=',' read -ra RAW_SELECTION <<< "$SELECTION"

            for item in "${RAW_SELECTION[@]}"; do

                item="$(echo "$item" | xargs)"

                [[ -z "$item" ]] && continue

                if [[ "$item" =~ ^[0-9]+$ ]]; then

                    idx=$((item - 1))

                    if [[ -n "${AVAILABLE_MODULES[$idx]:-}" ]]; then
                        NEW_MODULES+=("${AVAILABLE_MODULES[$idx]}")
                    else
                        warn "Invalid selection: $item"
                    fi

                else

                    NEW_MODULES+=("$item")

                fi

            done

        fi

        TRIMMED_MODULES=()

        for m in "${NEW_MODULES[@]}"; do
            m="$(echo "$m" | xargs)"
            [[ -n "$m" ]] && TRIMMED_MODULES+=("$m")
        done

        create_profile "$PROFILE_ID" "$NAME" "$DESCRIPTION" "${TRIMMED_MODULES[@]}"

        ;;

    help|*)

        section "Profile"

        cat <<EOF
Usage:
    hyprx profile list
    hyprx profile current
    hyprx profile show <profile>
    hyprx profile use <profile>
    hyprx profile create <id> [--name NAME] [--description DESC] [--modules mod1,mod2]
EOF
        ;;

esac