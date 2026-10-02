#!/usr/bin/env bash

# Automatic dGPU offload for heavy apps
#
# Linux has no true automatic per-app GPU switching (see prime-run.sh), so this
# generates .desktop overrides wrapping each Exec= line in the PRIME env vars.

# GPU-heavy apps list - edit it here, or create ~/.config/hyprx/gpu-apps.conf
# with one .desktop base name per line.
GPU_APPS_FILE="${HYPRX_CONFIG:-$HOME/.config/hyprx}/gpu-apps.conf"

if [[ -f "$GPU_APPS_FILE" ]]; then
    mapfile -t GPU_HEAVY_APPS < <(grep -v '^#' "$GPU_APPS_FILE" | grep -v '^$')
else
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
fi

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

    # Rewrite every Exec= line to run through the offload env, unless it's
    # already wrapped - makes this idempotent to re-run against its own output.
    awk -v prefix="$OFFLOAD_ENV" '
        /^Exec=/ && index($0, prefix) == 0 {
            sub(/^Exec=/, "Exec=" prefix " ")
        }
        { print }
    ' "$source_file" > "$target_file"

    echo "GPU offload enabled: $app"
done
