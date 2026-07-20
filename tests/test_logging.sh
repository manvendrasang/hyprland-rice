#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

rm -f "$LOG_FILE"

info "Info"

warn "Warning"

error "Error"

success "Success"

[[ -f "$LOG_FILE" ]]

grep -q INFO "$LOG_FILE"

grep -q WARN "$LOG_FILE"

grep -q ERROR "$LOG_FILE"

grep -q SUCCESS "$LOG_FILE"

echo "Logger OK."