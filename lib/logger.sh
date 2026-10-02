#!/usr/bin/env bash

# HYPRX_LOGGER_DIR is overridable so tests and sandboxes stay out of the real
# ~/.local/state/hyprx.
HYPRX_LOGGER_DIR="${HYPRX_LOGGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}"
HYPRX_LOGGER_FILE="$HYPRX_LOGGER_DIR/hyprx.log"

mkdir -p "$HYPRX_LOGGER_DIR" 2>/dev/null || true

hyprx_logger_rank() {
  case "$1" in
    DEBUG)        printf '10\n' ;;
    WARN)         printf '30\n' ;;
    ERROR)        printf '40\n' ;;
    INFO|SUCCESS) printf '20\n' ;;
    *)            printf '20\n' ;;
  esac
}

# Read at call time, not source time: lib/config.sh is sourced after this file,
# so HYPRX_CONFIG_LOG_LEVEL is unset while this is being defined.
hyprx_logger_enabled() {
  local level="$1"

  case "$level" in
    DEBUG|INFO|SUCCESS|WARN|ERROR) ;;
    *) return 0 ;;   # unknown level: never suppress
  esac

  local threshold
  case "${HYPRX_CONFIG_LOG_LEVEL:-info}" in
    off)   threshold=999 ;;
    error) threshold=40 ;;
    warn)  threshold=30 ;;
    info)  threshold=20 ;;
    debug) threshold=10 ;;
    *)     threshold=20 ;;
  esac

  (( $(hyprx_logger_rank "$level") >= threshold ))
}

hyprx_logger_log() {
  local level="$1"
  shift

  hyprx_logger_enabled "$level" || return 0

  printf "[%s] [%s] %s\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$level" \
    "$*" >>"$HYPRX_LOGGER_FILE" 2>/dev/null || true
}

hyprx_logger_info() {
  hyprx_logger_log INFO "$@"
}

hyprx_logger_warn() {
  hyprx_logger_log WARN "$@"
}

hyprx_logger_error() {
  hyprx_logger_log ERROR "$@"
}

hyprx_logger_success() {
  hyprx_logger_log SUCCESS "$@"
}
