#!/usr/bin/env bash

# -----------------------------
# Operating System
# -----------------------------

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    HYPRX_DETECT_DISTRO="$ID"
    HYPRX_DETECT_DISTRO_NAME="$PRETTY_NAME"
else
    HYPRX_DETECT_DISTRO="unknown"
    HYPRX_DETECT_DISTRO_NAME="Unknown"
fi

# -----------------------------
# Package Manager
# -----------------------------

HYPRX_DETECT_PACKAGE_MANAGER="unknown"

if command -v yay >/dev/null 2>&1; then
    HYPRX_DETECT_PACKAGE_MANAGER="yay"
elif command -v paru >/dev/null 2>&1; then
    HYPRX_DETECT_PACKAGE_MANAGER="paru"
elif command -v pacman >/dev/null 2>&1; then
    HYPRX_DETECT_PACKAGE_MANAGER="pacman"
fi

# -----------------------------
# CPU
# -----------------------------

# Every probe here is `|| true`-guarded. These run at source time, and
# detect.sh is sourced by bootstrap.sh inside callers running under
# `set -e -o pipefail`. Without the guard a single missing probe tool
# (lscpu/lspci/ip on a minimal container) failed the whole pipeline with a
# bare exit 127 and no output at all.
HYPRX_DETECT_CPU_VENDOR=$(lscpu 2>/dev/null | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2}' || true)
[[ -n "$HYPRX_DETECT_CPU_VENDOR" ]] || HYPRX_DETECT_CPU_VENDOR="unknown"

# -----------------------------
# GPU
# -----------------------------

HYPRX_DETECT_GPU_VENDOR="unknown"

HYPRX_DETECT_LSPCI=$(lspci 2>/dev/null || true)

if grep -qi nvidia <<<"$HYPRX_DETECT_LSPCI"; then
    HYPRX_DETECT_GPU_VENDOR="nvidia"
elif grep -Eqi "amd|advanced micro devices" <<<"$HYPRX_DETECT_LSPCI"; then
    HYPRX_DETECT_GPU_VENDOR="amd"
elif grep -qi intel <<<"$HYPRX_DETECT_LSPCI"; then
    HYPRX_DETECT_GPU_VENDOR="intel"
fi

# -----------------------------
# Battery
# -----------------------------

HYPRX_DETECT_BATTERY_NAME=$(ls /sys/class/power_supply 2>/dev/null | grep '^BAT' | head -n1 || true)

HYPRX_DETECT_HAS_BATTERY=false
[[ -n "$HYPRX_DETECT_BATTERY_NAME" ]] && HYPRX_DETECT_HAS_BATTERY=true || true

# -----------------------------
# Network
# -----------------------------

HYPRX_DETECT_NETWORK_INTERFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}' || true)

# -----------------------------
# Bluetooth
# -----------------------------

HYPRX_DETECT_HAS_BLUETOOTH=false
command -v bluetoothctl >/dev/null 2>&1 && HYPRX_DETECT_HAS_BLUETOOTH=true || true

# -----------------------------
# PipeWire
# -----------------------------

HYPRX_DETECT_HAS_PIPEWIRE=false
pgrep pipewire >/dev/null 2>&1 && HYPRX_DETECT_HAS_PIPEWIRE=true || true

# -----------------------------
# Waybar
# -----------------------------

HYPRX_DETECT_HAS_WAYBAR=false
command -v waybar >/dev/null 2>&1 && HYPRX_DETECT_HAS_WAYBAR=true || true

# -----------------------------
# Rofi
# -----------------------------

HYPRX_DETECT_HAS_ROFI=false
command -v rofi >/dev/null 2>&1 && HYPRX_DETECT_HAS_ROFI=true || true

# -----------------------------
# Kitty
# -----------------------------

HYPRX_DETECT_HAS_KITTY=false
command -v kitty >/dev/null 2>&1 && HYPRX_DETECT_HAS_KITTY=true || true

# -----------------------------
# VS Code
# -----------------------------

HYPRX_DETECT_HAS_CODE=false
command -v code >/dev/null 2>&1 && HYPRX_DETECT_HAS_CODE=true || true

# -----------------------------
# Neovim
# -----------------------------

HYPRX_DETECT_HAS_NVIM=false
command -v nvim >/dev/null 2>&1 && HYPRX_DETECT_HAS_NVIM=true || true

# -----------------------------
# Git
# -----------------------------

HYPRX_DETECT_HAS_GIT=false
command -v git >/dev/null 2>&1 && HYPRX_DETECT_HAS_GIT=true || true

# -----------------------------
# SwayNC
# -----------------------------

HYPRX_DETECT_HAS_SWAYNC=false
command -v swaync >/dev/null 2>&1 && HYPRX_DETECT_HAS_SWAYNC=true || true

# -----------------------------
# Hyprland
# -----------------------------

HYPRX_DETECT_HAS_HYPRLAND=false
[[ "${XDG_CURRENT_DESKTOP:-}" == "Hyprland" ]] && HYPRX_DETECT_HAS_HYPRLAND=true || true

# -----------------------------
# Power Profiles
# -----------------------------

HYPRX_DETECT_HAS_POWER_PROFILE=false
command -v powerprofilesctl >/dev/null 2>&1 && HYPRX_DETECT_HAS_POWER_PROFILE=true || true

# -----------------------------
# ZRAM
# -----------------------------

HYPRX_DETECT_HAS_ZRAM=false
(grep -q zram /proc/swaps 2>/dev/null && HYPRX_DETECT_HAS_ZRAM=true) || true
