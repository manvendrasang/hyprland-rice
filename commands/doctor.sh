#!/usr/bin/env bash

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
COMMAND_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(dirname "$COMMAND_DIR")"

source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/utils.sh"
source "$ROOT_DIR/lib/logger.sh"
source "$ROOT_DIR/lib/detect.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/modules.sh"
source "$ROOT_DIR/lib/table.sh"

header
info_log "Running doctor"

success_log "Doctor finished"

check() {
  if [[ "$2" == true ]]; then
    success "$1"
  else
    error "$1"
  fi
}

echo

echo "Configuration"
echo "────────────────────────────────────────"

table_header

table_row "Profile"        "$PROFILE"
table_row "Theme"          "$THEME"
table_row "Terminal"       "$TERMINAL"
table_row "Browser"        "$BROWSER"
table_row "Editor"         "$EDITOR"
table_row "File Manager"   "$FILE_MANAGER"
table_row "Launcher"       "$LAUNCHER"
echo

echo "Applications"
echo "────────────────────────────────────────"

check "Waybar Installed" "$HAS_WAYBAR"
check "Rofi Installed" "$HAS_ROFI"
check "Kitty Installed" "$HAS_KITTY"
check "VS Code Installed" "$HAS_CODE"
check "Neovim Installed" "$HAS_NVIM"
check "Git Installed" "$HAS_GIT"
check "SwayNC Installed" "$HAS_SWAYNC"

echo

echo

echo "System Information"
echo "────────────────────────────────────────"

table_header

table_row "Distribution"        "$DISTRO_NAME"
table_row "Package Manager"     "$PACKAGE_MANAGER"
table_row "CPU Vendor"          "$CPU_VENDOR"
table_row "GPU Vendor"          "$GPU_VENDOR"
table_row "Battery"             "${BATTERY_NAME:-None}"
table_row "Network Interface"   "${NETWORK_INTERFACE:-Unknown}"
table_row "Hyprland"            "$HAS_HYPRLAND"
table_row "PipeWire"            "$HAS_PIPEWIRE"
table_row "Bluetooth"           "$HAS_BLUETOOTH"
table_row "Waybar"              "$HAS_WAYBAR"
table_row "Rofi"                "$HAS_ROFI"
table_row "Kitty"               "$HAS_KITTY"
table_row "VS Code"             "$HAS_CODE"
table_row "Neovim"              "$HAS_NVIM"
table_row "Git"                 "$HAS_GIT"
table_row "SwayNC"              "$HAS_SWAYNC"
table_row "ZRAM"                "$HAS_ZRAM"
table_row "Power Profiles"      "$HAS_POWER_PROFILE"
echo

echo "Storage"
echo "────────────────────────────────────────"

root_usage=$(df / | awk 'NR==2 {print $5}')
info "Root Usage         : $root_usage"

echo

echo "Memory"
echo "────────────────────────────────────────"

free -h

echo

echo "Swap"
echo "────────────────────────────────────────"

swapon --show

echo

echo "Systemd"
echo "────────────────────────────────────────"

if systemctl --failed --no-legend | grep -q .; then
  warn "Failed services detected"
  echo
  systemctl --failed --no-pager
else
  success "No failed services"
fi

echo

echo "Pacman"
echo "────────────────────────────────────────"

if [[ -f /var/lib/pacman/db.lck ]]; then
  warn "Pacman database is locked"
else
  success "Pacman database unlocked"
fi

echo

success "Doctor completed."


echo

echo "Modules"
echo "────────────────────────────────────────"

discover_modules

table_header

for module in "${AVAILABLE_MODULES[@]}"; do

    module_validate "$module"

    case $? in

        0)
            status="OK"
            ;;

        1)
            status="Missing module.conf"
            ;;

        2)
            status="Missing packages.list"
            ;;

        3)
            status="Missing services.list"
            ;;

    esac

    table_row "$module" "$status"

done