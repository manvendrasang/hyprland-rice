#!/usr/bin/env bash

# Runs at source time inside callers using `set -e -o pipefail`, so every
# probe here is `|| true`-guarded: one missing tool (lscpu/lspci/ip on a
# minimal container) would otherwise abort bootstrap with a bare exit 127.

# --- Helpers, defined first because they are used throughout ---------------
#
# The capability checks below were each written as
#
#     command -v X >/dev/null 2>&1 && HYPRX_DETECT_HAS_X=true || true
#
# which is `A && B || C`. ShellCheck flags it (SC2015) for a good reason: C is
# not an else branch, it is a third statement that happens to run when B fails.
# Here B is an assignment, which cannot fail, so C was unreachable in practice -
# but the shape is a landmine, it is why this file's lines read as one mistake
# repeated, and CI's ShellCheck flagged thirteen of them at once.
#
# `detect_capability` does the same job with one shape, no SC2015, and no
# trailing `|| true`: it assigns true or false unconditionally and always
# returns 0, so a failing probe can never abort the file.
#
#   detect_capability VAR command...   # probe succeeds -> true
#   detect_capability VAR test...      # a full test command; its status is the answer

detect_capability() {
    local __var="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        printf -v "$__var" '%s' "true"
    else
        printf -v "$__var" '%s' "false"
    fi

    # Explicit, so a failing probe cannot trip a caller's errexit.
    return 0
}

# Shorthand for the common case: is this executable on PATH?
detect_command() {
    local __var="$1"
    shift
    detect_capability "$__var" command -v "$@"
}

# Shorthand for "is this process running".
detect_process() {
    local __var="$1"
    shift
    detect_capability "$__var" pgrep -x "$@"
}

# --- Operating system ---

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    HYPRX_DETECT_DISTRO="$ID"
    HYPRX_DETECT_DISTRO_NAME="$PRETTY_NAME"
else
    HYPRX_DETECT_DISTRO="unknown"
    HYPRX_DETECT_DISTRO_NAME="Unknown"
fi

# --- Package manager ---

HYPRX_DETECT_PACKAGE_MANAGER="unknown"

if command -v yay >/dev/null 2>&1; then
    HYPRX_DETECT_PACKAGE_MANAGER="yay"
elif command -v paru >/dev/null 2>&1; then
    HYPRX_DETECT_PACKAGE_MANAGER="paru"
elif command -v pacman >/dev/null 2>&1; then
    HYPRX_DETECT_PACKAGE_MANAGER="pacman"
fi

# --- Hardware ---

HYPRX_DETECT_CPU_VENDOR=$(lscpu 2>/dev/null | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2}' || true)
[[ -n "$HYPRX_DETECT_CPU_VENDOR" ]] || HYPRX_DETECT_CPU_VENDOR="unknown"

HYPRX_DETECT_GPU_VENDOR="unknown"
HYPRX_DETECT_LSPCI=$(lspci 2>/dev/null || true)

if grep -qi nvidia <<<"$HYPRX_DETECT_LSPCI"; then
    HYPRX_DETECT_GPU_VENDOR="nvidia"
elif grep -Eqi "amd|advanced micro devices" <<<"$HYPRX_DETECT_LSPCI"; then
    HYPRX_DETECT_GPU_VENDOR="amd"
elif grep -qi intel <<<"$HYPRX_DETECT_LSPCI"; then
    HYPRX_DETECT_GPU_VENDOR="intel"
fi

HYPRX_DETECT_BATTERY_NAME=$(ls /sys/class/power_supply 2>/dev/null | grep '^BAT' | head -n1 || true)
# Same `A && B || C` shape as the ones below, and easy to miss when fixing them
# in bulk - this one sat above the helper's original definition.
detect_capability HYPRX_DETECT_HAS_BATTERY test -n "$HYPRX_DETECT_BATTERY_NAME"

HYPRX_DETECT_NETWORK_INTERFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}' || true)

# --- Capabilities ---

detect_command  HYPRX_DETECT_HAS_BLUETOOTH     bluetoothctl
detect_process HYPRX_DETECT_HAS_PIPEWIRE      pipewire
detect_command  HYPRX_DETECT_HAS_WAYBAR        waybar
detect_command  HYPRX_DETECT_HAS_ROFI          rofi
detect_command  HYPRX_DETECT_HAS_KITTY         kitty
detect_command  HYPRX_DETECT_HAS_CODE          code
detect_command  HYPRX_DETECT_HAS_NVIM          nvim
detect_command  HYPRX_DETECT_HAS_GIT           git
detect_command  HYPRX_DETECT_HAS_SWAYNC        swaync
detect_command  HYPRX_DETECT_HAS_POWER_PROFILE powerprofilesctl

# The active session, not the installed one: XDG_CURRENT_DESKTOP is set by the
# session you are logged into.
detect_capability HYPRX_DETECT_HAS_HYPRLAND \
    test "${XDG_CURRENT_DESKTOP:-}" = "Hyprland"

# ZRAM. /proc/swaps lists one device per line, so a substring match is the test.
detect_capability HYPRX_DETECT_HAS_ZRAM grep -q zram /proc/swaps
