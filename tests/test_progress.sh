#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing progress..."

for i in {1..10}; do
    progress "$i" 10 >/dev/null
done

echo

table_header

table_row "Test" "OK"

echo "Progress utilities OK."