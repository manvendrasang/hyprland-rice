#!/usr/bin/env bash

BAT="/sys/class/power_supply/BAT1"

capacity=$(<"$BAT/capacity")
status=$(<"$BAT/status")

charge_now=$(<"$BAT/charge_now")
charge_full=$(<"$BAT/charge_full")

current=$(<"$BAT/current_now")
voltage=$(<"$BAT/voltage_now")

cycles=$(<"$BAT/cycle_count")

health=$(awk "BEGIN{printf \"%.0f\", ($charge_full/$(<"$BAT/charge_full_design"))*100}")

power=$(awk "BEGIN{
printf \"%.1f\", ($current*$voltage)/1000000000000
}")

if [[ "$current" -gt 0 ]]; then

    if [[ "$status" == "Charging" ]]; then

        remaining=$(awk "BEGIN{
        h=(($charge_full-$charge_now)/$current)
        printf \"%dh %02dm\", h,(h-int(h))*60
        }")

    else

        remaining=$(awk "BEGIN{
        h=($charge_now/$current)
        printf \"%dh %02dm\", h,(h-int(h))*60
        }")

    fi

else

    remaining="--"

fi

case "$status" in

Charging)
icon="󰂄"
;;

Full)
icon="󰁹"
;;

*)

if (( capacity >= 90 )); then
icon="󰂂"

elif (( capacity >= 70 )); then
icon="󰂀"

elif (( capacity >= 50 )); then
icon="󰁾"

elif (( capacity >= 30 )); then
icon="󰁼"

elif (( capacity >= 15 )); then
icon="󰁺"

else
icon="󰂎"

fi
;;

esac

printf '{"text":"%s %s%%","tooltip":"%s\nTime: %s\nPower: %sW\nHealth: %s%%\nCycles: %s"}\n' \
"$icon" \
"$capacity" \
"$status" \
"$remaining" \
"$power" \
"$health" \
"$cycles"