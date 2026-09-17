#!/usr/bin/env bash
# Event-driven trigger for the custom/bluetooth module.
#
# bluetoothctl has no clean non-interactive --follow mode, so instead
# this watches BlueZ's own D-Bus PropertiesChanged signals and just
# pokes Waybar to re-run bluetooth.sh when something changes. It
# deliberately never parses the signal payload itself - bluetooth.sh
# still does the actual bluetoothctl query - which keeps this daemon
# unaffected by BlueZ D-Bus schema differences across versions.
#
# config.jsonc also keeps a long (30s) interval as a safety net in
# case this daemon isn't running or dbus-monitor is unavailable.

set -uo pipefail

command -v dbus-monitor >/dev/null 2>&1 || exit 0
command -v bluetoothctl >/dev/null 2>&1 || exit 0

dbus-monitor --system \
    "type='signal',interface='org.freedesktop.DBus.Properties',path_namespace='/org/bluez'" 2>/dev/null |
while IFS= read -r _line; do
    pkill -RTMIN+10 waybar 2>/dev/null
done
