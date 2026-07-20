#!/usr/bin/env bash

set -euo pipefail

echo "Running ShellCheck..."

find . -name "*.sh" -print0 |
while IFS= read -r -d '' file; do
    shellcheck "$file"
done

echo "ShellCheck OK."