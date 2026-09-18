#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Checking helper scripts..."

for script in \
    backup-config.sh \
    dev-sync.sh \
    reload-hypr.sh \
    reload-waybar.sh
do

    [[ -x "$ROOT_DIR/scripts/$script" ]]

done

echo "Scripts OK."