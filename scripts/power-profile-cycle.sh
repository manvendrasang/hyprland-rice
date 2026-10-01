#!/usr/bin/env bash

########################################
# SUPER+F5: power profile cycle
########################################
#
# Cycles through ASUS fan/power profiles:
#   AC:     Quiet -> Balanced -> Performance
#   Battery: Quiet -> Balanced (skips Performance)
#
# Uses `asusctl profile set` to directly set the next
# profile in the cycle, confirmed working on this
# machine (SUPER+F6).
#
# rog-control-center already auto-switches AC/Battery
# profile on its own - this is just the manual override.
#

get_active_profile() {
    asusctl profile get | awk -F': ' '/Active profile/ {print $2}'
}

is_on_ac() {
    local supply
    for supply in /sys/class/power_supply/*/type; do
        [[ -f "$supply" ]] || continue
        if [[ "$(cat "$supply" 2>/dev/null)" == "Mains" ]]; then
            local online="${supply%/type}/online"
            [[ -f "$online" ]] && [[ "$(cat "$online" 2>/dev/null)" == "1" ]] && return 0
        fi
    done
    return 1
}

get_next_profile() {
    local current="$1"
    local on_ac="$2"

    case "$current" in
        Quiet)
            echo "Balanced"
            ;;
        Balanced)
            if [[ "$on_ac" == "true" ]]; then
                echo "Performance"
            else
                echo "Quiet"
            fi
            ;;
        Performance)
            echo "Quiet"
            ;;
        *)
            echo "Balanced"
            ;;
    esac
}

main() {
    local current
    current="$(get_active_profile)"

    local on_ac="false"
    if is_on_ac; then
        on_ac="true"
    fi

    local next
    next="$(get_next_profile "$current" "$on_ac")"

    printf "Power Profile: %s -> %s\n" "$current" "$next"
    asusctl profile set "$next"

    notify-send "Power Profile" "$(get_active_profile)"
}

main
