#!/usr/bin/env bash

########################################
# Colors
########################################

HYPRX_UI_RED="\033[1;31m"
HYPRX_UI_GREEN="\033[1;32m"
HYPRX_UI_YELLOW="\033[1;33m"
HYPRX_UI_BLUE="\033[1;34m"
HYPRX_UI_CYAN="\033[1;36m"
HYPRX_UI_MAGENTA="\033[1;35m"
HYPRX_UI_RESET="\033[0m"

########################################
# Header
########################################

hyprx_ui_header() {

  if [[ -n "${TERM:-}" ]] && [[ -t 1 ]]; then
        clear
  fi

  echo -e "${HYPRX_UI_BLUE}"
  echo "╔════════════════════════════════════════════╗"
  echo "║                  HyprX                     ║"
  echo "╚════════════════════════════════════════════╝"
  echo -e "${HYPRX_UI_RESET}"

}

########################################
# Divider
########################################

hyprx_ui_divider() {

  printf '%*s\n' 80 '' | tr ' ' '='

}

########################################
# Section header
########################################

# shellcheck disable=SC2317,SC2329  # called indirectly via commands/*.sh, dynamically sourced by bin/hyprx
hyprx_ui_section() {
  echo
  echo -e "${HYPRX_UI_CYAN}== $1 ==${HYPRX_UI_RESET}"

}

########################################
# Banner
########################################

hyprx_ui_banner() {

  hyprx_ui_divider
  echo "$1"
  hyprx_ui_divider

}

########################################
# Logging helpers
########################################

hyprx_ui_success() {

  echo -e "${HYPRX_UI_GREEN}✓${HYPRX_UI_RESET} $1"
  hyprx_logger_success "$1"

}

hyprx_ui_error() {

  echo -e "${HYPRX_UI_RED}✗${HYPRX_UI_RESET} $1"
  hyprx_logger_error "$1"

}

hyprx_ui_warn() {

  echo -e "${HYPRX_UI_YELLOW}!${HYPRX_UI_RESET} $1"
  hyprx_logger_warn "$1"

}

hyprx_ui_info() {

  echo -e "${HYPRX_UI_CYAN}>${HYPRX_UI_RESET} $1"
  hyprx_logger_info "$1"

}

########################################
# User Input
########################################

hyprx_ui_question() {

  read -rp "$(echo -e "${HYPRX_UI_MAGENTA}?${HYPRX_UI_RESET} $1 ")"

}

########################################
# Progress
########################################

hyprx_ui_progress_message() {

  local current="$1"
  local total="$2"

  printf "[%d/%d]\n" "$current" "$total"

}
