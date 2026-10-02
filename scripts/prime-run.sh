#!/usr/bin/env bash

# On-demand NVIDIA GPU offload
#
# Usage: prime-run <cmd> - everything runs on the integrated GPU by default, and
# this puts just that one process on the NVIDIA GPU.

export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only

exec "$@"
