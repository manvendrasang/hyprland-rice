#!/usr/bin/env bash

########################################
# HyprX settings menu (SUPER+I)
########################################
#
# There is no lightweight app that provides
# a single Windows-style settings panel and
# also actually runs under Hyprland -
# gnome-control-center refuses to start
# outside a GNOME/Unity session entirely.
#
# Instead, this is a rofi hub over the
# individual, purpose-built tool already
# installed for each category - each entry
# opens the single best tool for that job
# rather than reinventing it. Add or reorder
# entries by editing LABELS/COMMANDS below,
# keeping both arrays the same length and in
# the same order.
#

LABELS=(
    "󰈀  Network"
    "󰂯  Bluetooth"
    "󰕾  Sound"
    "󰍹  Displays"
    "󰉼  Personalization"
    "󰸉  Wallpaper"
    "󰂚  Notifications"
    "󰒃  Security (Firewall)"
    "󰀫  Power Profile (ASUS)"
    "󰍛  Hardware & Monitoring"
    "󰚰  System Update"
)

COMMANDS=(
    "nm-connection-editor"
    "blueman-manager"
    "pavucontrol"
    "nwg-displays"
    "nwg-look"
    "waypaper"
    "swaync-client -t"
    "firewall-config"
    "rog-control-center"
    "mission-center"
    "kitty --hold -e $HOME/.local/share/hyprx/bin/hyprx update"
)

CHOICE=$(
    printf '%s\n' "${LABELS[@]}" |
    rofi -dmenu \
        -i \
        -p "Settings" \
        -theme ~/.config/rofi/dmenu.rasi
)

[[ -z "$CHOICE" ]] && exit 0

CMD=""

for i in "${!LABELS[@]}"; do
    if [[ "${LABELS[$i]}" == "$CHOICE" ]]; then
        CMD="${COMMANDS[$i]}"
        break
    fi
done

[[ -z "$CMD" ]] && exit 0

BIN="${CMD%% *}"

if ! command -v "$BIN" >/dev/null 2>&1; then
    notify-send "HyprX Settings" "$BIN not found. Try: pacman -Q $BIN"
    exit 1
fi

# Intentional word-splitting - CMD is one of the fixed
# strings above, never external/user-controlled input.
# shellcheck disable=SC2086
exec $CMD
