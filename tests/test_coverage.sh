#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Checking library coverage..."

missing=0

for file in "$ROOT_DIR"/lib/**/*.sh "$ROOT_DIR"/lib/*.sh; do

    [[ -f "$file" ]] || continue

    basename="$(basename "$file")"

    # Skip the file itself - check if it's sourced somewhere
    if ! grep -rq "source.*$basename" "$ROOT_DIR/lib" "$ROOT_DIR/commands" "$ROOT_DIR/bin" 2>/dev/null; then
        echo "UNCOVERED: $basename (not sourced by any other file)"
        missing=$((missing + 1))
    else
        echo "Covered: $basename"
    fi

done

if [[ $missing -gt 0 ]]; then
    echo ""
    echo "FAIL: $missing file(s) not sourced by any other file"
    exit 1
fi

echo ""
echo "All library files are sourced. Coverage check passed."
