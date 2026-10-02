#!/usr/bin/env bash
# Event-driven trigger for the custom/bluetooth module.
# bluetoothctl has no non-interactive --follow mode, so watch BlueZ's D-Bus
# PropertiesChanged signals and just poke Waybar to re-run bluetooth.sh.

set -uo pipefail

command -v dbus-monitor >/dev/null 2>&1 || exit 0
command -v bluetoothctl >/dev/null 2>&1 || exit 0

dbus-monitor --system \
    "type='signal',interface='org.freedesktop.DBus.Properties',path_namespace='/org/bluez'" 2>/dev/null |
while IFS= read -r _line; do
    pkill -RTMIN+10 waybar 2>/dev/null
done
