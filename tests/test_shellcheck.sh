#!/usr/bin/env bash

set -euo pipefail

FAILED=0

while IFS= read -r -d '' file; do
    echo "Checking $file"

    if ! shellcheck -x "$file"; then
        FAILED=1
    fi

done < <(
    find . \
        -path "./.git" -prune -o \
        -path "./build" -prune -o \
        -path "./.cache" -prune -o \
        -name "*.sh" -print0
)

exit "$FAILED"