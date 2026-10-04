#!/usr/bin/env bash

# Terminal output helpers. Each printer writes to the terminal and records to
# the log; the log write honours HYPRX_CONFIG_LOG_LEVEL, terminal output does
# not, so warnings and errors are always visible.

HYPRX_UI_RED="\033[1;31m"
HYPRX_UI_GREEN="\033[1;32m"
HYPRX_UI_YELLOW="\033[1;33m"
HYPRX_UI_BLUE="\033[1;34m"
HYPRX_UI_CYAN="\033[1;36m"
HYPRX_UI_RESET="\033[0m"

hyprx_ui_header() {
  [[ -n "${TERM:-}" && -t 1 ]] && clear
  echo -e "${HYPRX_UI_BLUE}"
  echo "╔════════════════════════════════════════════╗"
  echo "║                  HyprX                     ║"
  echo "╚════════════════════════════════════════════╝"
  echo -e "${HYPRX_UI_RESET}"
}

hyprx_ui_divider() {
  printf '%*s\n' 80 '' | tr ' ' '='
}

# shellcheck disable=SC2317,SC2329  # reached via commands/*.sh, sourced by bin/hyprx
hyprx_ui_section() {
  echo
  echo -e "${HYPRX_UI_CYAN}== $1 ==${HYPRX_UI_RESET}"
}

# Every diagnostic goes to stderr. stdout is reserved for the thing the command
# actually produces - `hyprx doctor --json` emits a JSON document, and a stray
# warning on stdout makes it unparseable. This bit for real: the config loader
# warns about an unknown key in hyprx.conf, and that warning landed on stdout,
# so `doctor --json` returned a document prefixed by
#   ! Unknown key in hyprx.conf: NOT_A_KEY
# which is not JSON. The warning was invisible in a terminal because both
# streams look the same there.
#
# `hyprx_ui_header` and `hyprx_ui_divider` are the exceptions: they are chrome
# for a human reading a terminal, not output a caller parses.
hyprx_ui_success() {
  echo -e "${HYPRX_UI_GREEN}✓${HYPRX_UI_RESET} $1" >&2
  hyprx_logger_success "$1"
}

hyprx_ui_error() {
  echo -e "${HYPRX_UI_RED}✗${HYPRX_UI_RESET} $1" >&2
  hyprx_logger_error "$1"
}

hyprx_ui_warn() {
  echo -e "${HYPRX_UI_YELLOW}!${HYPRX_UI_RESET} $1" >&2
  hyprx_logger_warn "$1"
}

hyprx_ui_info() {
  echo -e "${HYPRX_UI_CYAN}>${HYPRX_UI_RESET} $1" >&2
  hyprx_logger_info "$1"
}
