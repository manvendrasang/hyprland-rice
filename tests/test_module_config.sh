#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/bootstrap.sh"

echo "Checking module metadata..."

for module in "$HYPRX_MODULES"/*; do

    [[ -d "$module" ]] || continue

    source "$module/module.conf"

    [[ -n "$NAME" ]]
    [[ -n "$PACKAGE_FILE" ]]

done

echo "Module metadata OK."