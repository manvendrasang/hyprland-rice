#!/usr/bin/env bash

LOG_DIR="$HOME/.local/state/hyprx"
LOG_FILE="$LOG_DIR/hyprx.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {

  local level="$1"
  shift

  printf "[%s] [%s] %s\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$level" \
    "$*" >>"$LOG_FILE" 2>/dev/null || true
}

info_log() {
  log INFO "$@"
}

warn_log() {
  log WARN "$@"
}

error_log() {
  log ERROR "$@"
}

success_log() {
  log SUCCESS "$@"
}