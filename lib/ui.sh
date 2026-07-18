#!/usr/bin/env bash

########################################
# Colors
########################################

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
RESET="\033[0m"

########################################
# Header
########################################

header() {

    clear

    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════╗"
    echo "║                  HyprX                     ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${RESET}"

}

########################################
# Divider
########################################

divider() {

    printf '%*s\n' 80 '' | tr ' ' '='

}

########################################
# Banner
########################################

banner() {

    divider
    echo "$1"
    divider

}

########################################
# Logging helpers
########################################

success() {

    echo -e "${GREEN}✓${RESET} $1"
    success_log "$1"

}

error() {

    echo -e "${RED}✗${RESET} $1"
    error_log "$1"

}

warn() {

    echo -e "${YELLOW}!${RESET} $1"
    warn_log "$1"

}

info() {

    echo -e "${CYAN}>${RESET} $1"
    info_log "$1"

}

########################################
# User Input
########################################

question() {

    read -rp "$(echo -e "${MAGENTA}?${RESET} $1 ")" reply

}

########################################
# Progress
########################################

progress_message() {

    local current="$1"
    local total="$2"

    printf "[%d/%d]\n" "$current" "$total"

}