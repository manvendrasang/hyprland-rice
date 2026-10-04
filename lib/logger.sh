#!/usr/bin/env bash

# Paths come from lib/state.sh.

# NOTE: HYPRX_LOGGER_DIR is deliberately NOT assigned here. It is the
# back-compat OVERRIDE - lib/state.sh:28-30 honours it when it is non-empty and
# otherwise leaves HYPRX_STATE_DIR alone. Writing the derived value back into
# that name turns "not set" into a concrete path, and because the test suite
# exports it (as "" meaning "derive it"), the assignment stayed exported: every
# child process then inherited it and state.sh used it to OVERRIDE its own
# HYPRX_STATE_DIR.
#
# The effect was that no child honoured the state dir it was given. The e2e
# install tests set HYPRX_STATE_DIR to a sandbox, and every log, snapshot,
# backup and install.state still landed under the suite-level dir - so
# "install.state cleared on success" and "install.state cleared after a partial
# install" were asserting against a directory the install never wrote to.
HYPRX_LOGGER_FILE="$HYPRX_STATE_LOG_FILE"

# Rotate before the file crosses this size, keeping one previous generation.
# Without this the log grew without bound - there was no rotation anywhere.
HYPRX_LOG_MAX_BYTES="${HYPRX_LOG_MAX_BYTES:-2097152}"   # 2 MiB
HYPRX_LOG_KEEP="${HYPRX_LOG_KEEP:-1}"

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

hyprx_logger_rotate_if_needed() {
  local size
  size="$(hyprx_state_size "$HYPRX_LOGGER_FILE")"
  [[ -z "$size" ]] && return 0
  (( size < HYPRX_LOG_MAX_BYTES )) && return 0

    local i
    # Shift .N -> .N+1, dropping anything past the keep count.
    for ((i = HYPRX_LOG_KEEP - 1; i >= 1; i--)); do
        if [[ -f "$HYPRX_LOGGER_FILE.$i" ]]; then
            mv -f "$HYPRX_LOGGER_FILE.$i" "$HYPRX_LOGGER_FILE.$((i + 1))" 2>/dev/null || true
        fi
    done
    mv -f "$HYPRX_LOGGER_FILE" "$HYPRX_LOGGER_FILE.1" 2>/dev/null || true
    : >"$HYPRX_LOGGER_FILE" 2>/dev/null || true
}

hyprx_logger_log() {
  local level="$1"
  shift

  # Unknown levels are always recorded - see hyprx_logger_enabled - so a typo
  # here can never cause a message to be silently dropped.
  hyprx_logger_enabled "$level" || return 0

  hyprx_logger_rotate_if_needed

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
