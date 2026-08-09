#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing installer pipeline..."

# Bootstrap
[[ "${HYPRX_INITIALIZED:-false}" == "true" ]]

# The flat package manifest should exist and resolve into a queue
resolve_packages

[[ ${#PACKAGE_QUEUE[@]} -gt 0 ]]

# No duplicates after resolution
UNIQUE_COUNT="$(printf "%s\n" "${PACKAGE_QUEUE[@]}" | sort -u | wc -l)"

[[ "$UNIQUE_COUNT" -eq "${#PACKAGE_QUEUE[@]}" ]]

echo "Installer pipeline OK."
