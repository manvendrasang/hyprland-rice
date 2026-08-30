#!/usr/bin/env bash

########################################
# On-demand NVIDIA GPU offload
########################################
#
# Linux doesn't do fully-automatic, invisible
# GPU switching the way Windows Optimus does.
# This is the standard equivalent: everything
# runs on the efficient integrated GPU by
# default, and you explicitly run specific
# GPU-heavy apps through this wrapper to put
# just that one process on the NVIDIA GPU.
#
# Usage:
#     prime-run steam
#     prime-run glxinfo | grep vendor
#

export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only

exec "$@"
