#!/usr/bin/env bash

set -euo pipefail

FAILED=0

while IFS= read -r -d '' file; do
    echo "Checking $file"

    if ! shellcheck \
    -x \
    -e SC1090,SC1091,SC2010,SC2015,SC2034,SC2086 \
    "$file"; then
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