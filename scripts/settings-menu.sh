#!/usr/bin/env bash

# HyprX settings menu (SUPER+I)
#
# gnome-control-center will not start outside a GNOME/Unity session, so this is a rofi hub over
# the tool already installed per category. Edit LABELS/COMMANDS, keeping both arrays aligned.

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
