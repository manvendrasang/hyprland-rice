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

    help|*)

        section "Profile"

        cat <<EOF
Usage:
    hyprx profile list
    hyprx profile current
    hyprx profile show <profile>
    hyprx profile use <profile>
EOF
        ;;

esac