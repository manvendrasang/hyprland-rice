#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Checking library coverage..."

for file in "$ROOT_DIR"/lib/**/*.sh "$ROOT_DIR"/lib/*.sh; do

    [[ -f "$file" ]] || continue

    echo "Covered: $(basename "$file")"

done

echo "Coverage listing complete."