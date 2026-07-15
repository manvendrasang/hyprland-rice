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

PACKAGE_MANAGER=""

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

if [[ -n "$BATTERY_NAME" ]]; then
  HAS_BATTERY=true
else
  HAS_BATTERY=false
fi

# -----------------------------
# Network
# -----------------------------

NETWORK_INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

# -----------------------------
# Bluetooth
# -----------------------------

if command -v bluetoothctl >/dev/null 2>&1; then
  HAS_BLUETOOTH=true
else
  HAS_BLUETOOTH=false
fi

# -----------------------------
# PipeWire
# -----------------------------

if pgrep pipewire >/dev/null 2>&1; then
  HAS_PIPEWIRE=true
else
  HAS_PIPEWIRE=false
fi

# -----------------------------
# Waybar
# -----------------------------

command -v waybar >/dev/null 2>&1 &&
  HAS_WAYBAR=true ||
  HAS_WAYBAR=false

# -----------------------------
# Rofi
# -----------------------------

command -v rofi >/dev/null 2>&1 &&
  HAS_ROFI=true ||
  HAS_ROFI=false

# -----------------------------
# Kitty
# -----------------------------

command -v kitty >/dev/null 2>&1 &&
  HAS_KITTY=true ||
  HAS_KITTY=false

# -----------------------------
# VS Code
# -----------------------------

command -v code >/dev/null 2>&1 &&
  HAS_CODE=true ||
  HAS_CODE=false

# -----------------------------
# Neovim
# -----------------------------

command -v nvim >/dev/null 2>&1 &&
  HAS_NVIM=true ||
  HAS_NVIM=false

# -----------------------------
# Git
# -----------------------------

command -v git >/dev/null 2>&1 &&
  HAS_GIT=true ||
  HAS_GIT=false

# -----------------------------
# SwayNC
# -----------------------------

command -v swaync >/dev/null 2>&1 &&
  HAS_SWAYNC=true ||
  HAS_SWAYNC=false

# -----------------------------
# Hyprland
# -----------------------------

if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]]; then
  HAS_HYPRLAND=true
else
  HAS_HYPRLAND=false
fi

# -----------------------------
# Power Profiles
# -----------------------------

command -v powerprofilesctl >/dev/null 2>&1 &&
  HAS_POWER_PROFILE=true ||
  HAS_POWER_PROFILE=false

# -----------------------------
# ZRAM
# -----------------------------

if grep -q zram /proc/swaps 2>/dev/null; then
  HAS_ZRAM=true
else
  HAS_ZRAM=false
fi
