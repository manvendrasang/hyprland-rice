#!/usr/bin/env bash

########################################
# SUPER+F5: power profile cycle
########################################
#
# asusctl's own CLI has no flag to query
# the current profile in a scriptable way
# beyond "profile get" (confirmed - there
# is no -p/-n flag; the real subcommands
# are next/list/get/set/tuning). Rather
# than guess at "set", this only ever uses
# the confirmed-working "next" and "get"
# subcommands: advance to the next profile
# in the normal 3-way cycle, then on
# battery, skip straight past Performance
# if that's where it landed - restricting
# battery to Quiet <-> Balanced while AC
# keeps the full Quiet -> Balanced ->
# Performance cycle.
#
# rog-control-center already auto-switches
# AC/Battery profile on its own - this is
# just the manual override cycle.
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

asusctl profile next

if ! is_on_ac; then
    if [[ "$(get_active_profile)" == "Performance" ]]; then
        asusctl profile next
    fi
fi

notify-send "Power Profile" "$(get_active_profile)"
