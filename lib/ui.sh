#!/usr/bin/env bash

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
RESET="\033[0m"

header() {
  clear
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════╗"
  echo "║                  HyprX                     ║"
  echo "╚════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

success() { echo -e "${GREEN}✓${RESET} $1"; }
error() { echo -e "${RED}✗${RESET} $1"; }
warn() { echo -e "${YELLOW}!${RESET} $1"; }
info() { echo -e "${CYAN}>${RESET} $1"; }

question() {
  read -rp "$(echo -e "${MAGENTA}?${RESET} $1 ")" reply
}
