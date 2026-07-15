#!/usr/bin/env bash

read UTIL MEM_USED MEM_TOTAL TEMP <<< "$(
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