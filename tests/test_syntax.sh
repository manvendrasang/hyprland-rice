#!/usr/bin/env bash

set -euo pipefail

echo "Checking shell syntax..."

find . -name "*.sh" -print0 |
while IFS= read -r -d '' file; do
    bash -n "$file"
done

echo "Syntax OK."