#!/usr/bin/env bash

# Overridable so the test suite (and any sandboxed run) writes to a
# throwaway state dir instead of the user's real ~/.local/state/hyprx.
HYPRX_LOGGER_DIR="${HYPRX_LOGGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}"
HYPRX_LOGGER_FILE="$HYPRX_LOGGER_DIR/hyprx.log"

mkdir -p "$HYPRX_LOGGER_DIR" 2>/dev/null || true

hyprx_logger_log() {

  local level="$1"
  shift

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
