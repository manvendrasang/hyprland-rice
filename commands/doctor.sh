#!/usr/bin/env bash

header
info_log "Running doctor"

echo

########################################
# Configuration
########################################

section "Configuration"

table_header
table_row "Profile"        "${PROFILE:-Unknown}"
table_row "Theme"          "${THEME:-Default}"
table_row "Terminal"       "${TERMINAL:-Unknown}"
table_row "Browser"        "${BROWSER:-Unknown}"
table_row "Editor"         "${EDITOR:-Unknown}"
table_row "File Manager"   "${FILE_MANAGER:-Unknown}"
table_row "Launcher"       "${LAUNCHER:-Unknown}"

echo

########################################
# Applications
########################################

section "Applications"

check() {

    local name="$1"
    local status="$2"

    if [[ "$status" == true ]]; then
        success "$name"
    else
        error "$name"
    fi

}

check "Hyprland Installed" "$HAS_HYPRLAND"
check "Waybar Installed" "$HAS_WAYBAR"
check "Rofi Installed" "$HAS_ROFI"
check "Kitty Installed" "$HAS_KITTY"
check "VS Code Installed" "$HAS_CODE"
check "Neovim Installed" "$HAS_NVIM"
check "Git Installed" "$HAS_GIT"
check "SwayNC Installed" "$HAS_SWAYNC"
check "PipeWire Installed" "$HAS_PIPEWIRE"
check "Bluetooth Installed" "$HAS_BLUETOOTH"

echo

########################################
# System Information
########################################

section "System Information"

table_header
table_row "Distribution"       "$DISTRO_NAME"
table_row "Package Manager"    "$PACKAGE_MANAGER"
table_row "CPU Vendor"         "$CPU_VENDOR"
table_row "GPU Vendor"         "$GPU_VENDOR"
table_row "Battery"            "${BATTERY_NAME:-None}"
table_row "Network Interface"  "${NETWORK_INTERFACE:-Unknown}"
table_row "ZRAM"               "$HAS_ZRAM"
table_row "Power Profiles"     "$HAS_POWER_PROFILE"

echo

########################################
# Storage
########################################

section "Storage"

root_usage="$(df -h / | awk 'NR==2 {print $5}')"

table_header
table_row "Root Usage" "$root_usage"

echo

########################################
# Memory
########################################

section "Memory"

free -h

echo

########################################
# Swap
########################################

section "Swap"

swapon --show || true

echo

########################################
# Systemd
########################################

section "Systemd"

if systemctl --failed --no-legend | grep -q .; then
    warn "Failed services detected"
    echo
    systemctl --failed --no-pager
else
    success "No failed services"
fi

echo

########################################
# Pacman
########################################

section "Pacman"

if [[ -f /var/lib/pacman/db.lck ]]; then
    warn "Pacman database is locked"
else
    success "Pacman database unlocked"
fi

echo

########################################
# Modules
########################################

section "Modules"

discover_modules

table_header

for module in "${AVAILABLE_MODULES[@]}"; do

    if load_module "$module"; then

        status="OK"

        [[ ! -f "$HYPRX_MODULES/$module/module.conf" ]] && status="Missing module.conf"
        [[ ! -f "$HYPRX_MODULES/$module/$PACKAGE_FILE" ]] && status="Missing $PACKAGE_FILE"

        if [[ -n "${SERVICE_FILE:-}" ]]; then
            [[ ! -f "$HYPRX_MODULES/$module/$SERVICE_FILE" ]] && status="Missing $SERVICE_FILE"
        fi

    else

        status="Invalid"

    fi

    table_row "$module" "$status"

done

echo

success "Doctor completed."
success_log "Doctor finished"