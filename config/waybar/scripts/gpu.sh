#!/usr/bin/env bash

########################################
# NVIDIA (dGPU)
########################################

NV_UTIL="N/A"
NV_TEMP="-"
NV_MEM_USED="-"
NV_MEM_TOTAL="-"

if command -v nvidia-smi >/dev/null 2>&1; then

    if read -r UTIL MEM_USED MEM_TOTAL TEMP <<<"$(
        nvidia-smi \
            --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null |
        tr ',' ' '
    )" && [[ -n "$UTIL" ]]; then
        NV_UTIL="$UTIL"
        NV_TEMP="$TEMP"
        NV_MEM_USED="$MEM_USED"
        NV_MEM_TOTAL="$MEM_TOTAL"
    fi

fi

########################################
# Intel (iGPU)
########################################
#
# Requires intel-gpu-tools. Reading GPU perf
# counters as a normal user needs the
# perf_event_paranoid sysctl set low enough -
# see README. If that hasn't been set, this
# fails silently and reports N/A rather than
# breaking the whole widget.
#

INTEL_UTIL="N/A"

if command -v intel_gpu_top >/dev/null 2>&1; then

    RAW="$(timeout 1.5 intel_gpu_top -J -o - 2>/dev/null)"

    PARSED="$(
        echo "$RAW" |
        grep -A2 '"Render/3D' |
        grep '"busy"' |
        tail -1 |
        grep -oE '[0-9]+\.[0-9]+' |
        head -1
    )"

    if [[ -n "$PARSED" ]]; then
        INTEL_UTIL="$(printf "%.0f" "$PARSED")"
    fi

fi

########################################
# Combine
########################################

printf '{"text":"󰢮 %s%%  󰍹 %s%%","tooltip":"NVIDIA: %s%%\\nTemperature: %s°C\\nVRAM: %s/%s MiB\\n\\nIntel iGPU: %s%%"}\n' \
    "$NV_UTIL" \
    "$INTEL_UTIL" \
    "$NV_UTIL" \
    "$NV_TEMP" \
    "$NV_MEM_USED" \
    "$NV_MEM_TOTAL" \
    "$INTEL_UTIL"
