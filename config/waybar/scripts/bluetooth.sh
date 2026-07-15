#!/usr/bin/env bash

if ! bluetoothctl show >/dev/null 2>&1; then
    exit 0
fi

POWER=$(bluetoothctl show | awk -F': ' '/Powered:/ {print $2}')

if [[ "$POWER" != "yes" ]]; then
    printf '{"text":"󰂲","tooltip":"Bluetooth Off","class":"off"}\n'
    exit 0
fi

DEVICE=$(bluetoothctl devices Connected 2>/dev/null | cut -d' ' -f3-)

if [[ -z "$DEVICE" ]]; then
    printf '{"text":"󰂯","tooltip":"Bluetooth On\\nNo Connected Device","class":"on"}\n'
else
    printf '{"text":"󰂱 %s","tooltip":"Connected\\n%s","class":"connected"}\n' \
        "$DEVICE" \
        "$DEVICE"
fi