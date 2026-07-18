#!/usr/bin/env bash

# -----------------------------
# Operating System
# -----------------------------

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO="$ID"
    DISTRO_NAME="$PRETTY_NAME"
else
    DISTRO="unknown"
    DISTRO_NAME="Unknown"
fi

# -----------------------------
# Package Manager
# -----------------------------

PACKAGE_MANAGER="unknown"

if command -v yay >/dev/null 2>&1; then
    PACKAGE_MANAGER="yay"
elif command -v paru >/dev/null 2>&1; then
    PACKAGE_MANAGER="paru"
elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
fi

# -----------------------------
# CPU
# -----------------------------

CPU_VENDOR=$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2}')

# -----------------------------
# GPU
# -----------------------------

GPU_VENDOR="unknown"

if lspci | grep -qi nvidia; then
    GPU_VENDOR="nvidia"
elif lspci | grep -Eqi "amd|advanced micro devices"; then
    GPU_VENDOR="amd"
elif lspci | grep -qi intel; then
    GPU_VENDOR="intel"
fi

# -----------------------------
# Battery
# -----------------------------

BATTERY_NAME=$(ls /sys/class/power_supply 2>/dev/null | grep '^BAT' | head -n1)

HAS_BATTERY=false
[[ -n "$BATTERY_NAME" ]] && HAS_BATTERY=true

# -----------------------------
# Network
# -----------------------------

NETWORK_INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

# -----------------------------
# Bluetooth
# -----------------------------

HAS_BLUETOOTH=false
command -v bluetoothctl >/dev/null 2>&1 && HAS_BLUETOOTH=true

# -----------------------------
# PipeWire
# -----------------------------

HAS_PIPEWIRE=false
pgrep pipewire >/dev/null 2>&1 && HAS_PIPEWIRE=true

# -----------------------------
# Waybar
# -----------------------------

HAS_WAYBAR=false
command -v waybar >/dev/null 2>&1 && HAS_WAYBAR=true

# -----------------------------
# Rofi
# -----------------------------

HAS_ROFI=false
command -v rofi >/dev/null 2>&1 && HAS_ROFI=true

# -----------------------------
# Kitty
# -----------------------------

HAS_KITTY=false
command -v kitty >/dev/null 2>&1 && HAS_KITTY=true

# -----------------------------
# VS Code
# -----------------------------

HAS_CODE=false
command -v code >/dev/null 2>&1 && HAS_CODE=true

# -----------------------------
# Neovim
# -----------------------------

HAS_NVIM=false
command -v nvim >/dev/null 2>&1 && HAS_NVIM=true

# -----------------------------
# Git
# -----------------------------

HAS_GIT=false
command -v git >/dev/null 2>&1 && HAS_GIT=true

# -----------------------------
# SwayNC
# -----------------------------

HAS_SWAYNC=false
command -v swaync >/dev/null 2>&1 && HAS_SWAYNC=true

# -----------------------------
# Hyprland
# -----------------------------

HAS_HYPRLAND=false
[[ "${XDG_CURRENT_DESKTOP:-}" == "Hyprland" ]] && HAS_HYPRLAND=true

# -----------------------------
# Power Profiles
# -----------------------------

HAS_POWER_PROFILE=false
command -v powerprofilesctl >/dev/null 2>&1 && HAS_POWER_PROFILE=true

# -----------------------------
# ZRAM
# -----------------------------

HAS_ZRAM=false
grep -q zram /proc/swaps 2>/dev/null && HAS_ZRAM=true