#!/usr/bin/env bash

########################################
# Automatic dGPU offload for heavy apps
########################################
#
# Linux has no true Windows-style automatic
# per-app GPU switching - see prime-run.sh
# for why. The practical equivalent is
# making sure specific GPU-heavy apps always
# launch on the dGPU without typing
# "prime-run" every time. This generates
# user-level .desktop overrides (which take
# priority over a system file of the same
# name) that wrap the app's Exec= line in
# the PRIME render-offload env vars.
#
# Only touches apps actually found on the
# system - anything not installed is skipped
# silently, no error. Safe to re-run any
# time (this runs on every `hyprx install`)
# - it just regenerates the same overrides,
# and is a no-op if they're already correct.
#
# To offload additional apps, add their
# .desktop file's base name (without the
# .desktop extension - check
# /usr/share/applications/ for the exact
# name) to GPU_HEAVY_APPS below.
#

GPU_HEAVY_APPS=(
    blender
    steam
    steam-native
    lutris
    net.lutris.Lutris
    com.heroicgameslauncher.hgl
    prismlauncher
    org.prismlauncher.PrismLauncher
    godot
    unityhub
)

OVERRIDE_DIR="${HYPRX_TARGET_HOME:-$HOME}/.local/share/applications"

SYSTEM_APP_DIRS=(
    "/usr/share/applications"
    "/usr/local/share/applications"
)

OFFLOAD_ENV="env __NV_PRIME_RENDER_OFFLOAD=1 __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"

mkdir -p "$OVERRIDE_DIR"

for app in "${GPU_HEAVY_APPS[@]}"; do

    source_file=""

    for dir in "${SYSTEM_APP_DIRS[@]}"; do
        if [[ -f "$dir/$app.desktop" ]]; then
            source_file="$dir/$app.desktop"
            break
        fi
    done

    [[ -z "$source_file" ]] && continue

    target_file="$OVERRIDE_DIR/$app.desktop"

    # Rewrite every Exec= line to run through the offload
    # env, unless it's already wrapped - makes this
    # idempotent to re-run against its own prior output.
    awk -v prefix="$OFFLOAD_ENV" '
        /^Exec=/ && index($0, prefix) == 0 {
            sub(/^Exec=/, "Exec=" prefix " ")
        }
        { print }
    ' "$source_file" > "$target_file"

    echo "GPU offload enabled: $app"

done
