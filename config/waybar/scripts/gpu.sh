#!/usr/bin/env bash

if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf '{"text":"󰢮 N/A","tooltip":"NVIDIA GPU not detected"}\n'
    exit 0
fi

read -r UTIL MEM_USED MEM_TOTAL TEMP <<<"$(
nvidia-smi \
    --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
    --format=csv,noheader,nounits |
tr ',' ' '
)"

printf '{"text":"󰢮 %s%%","tooltip":"GPU Usage: %s%%\\nTemperature: %s°C\\nVRAM: %s/%s MiB"}\n' \
    "$UTIL" \
    "$UTIL" \
    "$TEMP" \
    "$MEM_USED" \
    "$MEM_TOTAL"