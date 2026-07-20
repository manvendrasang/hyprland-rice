#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "Testing replacements..."

if [[ -f "$HYPRX_DATABASE/replacements.conf" ]]; then

    while IFS='=' read -r old new; do

        [[ -z "$old" ]] && continue

        [[ "$old" =~ ^# ]] && continue

        replacement="$(get_replacement "$old")"

        [[ "$replacement" == "$new" ]]

    done < "$HYPRX_DATABASE/replacements.conf"

fi

echo "Replacement database OK."