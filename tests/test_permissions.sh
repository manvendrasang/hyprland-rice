#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Checking executable scripts..."

find "$ROOT_DIR/bin" "$ROOT_DIR/scripts" -type f |
while IFS= read -r file; do

    [[ -x "$file" ]] || {
        echo "$file is not executable"
        exit 1
    }

done

echo "Permissions OK."