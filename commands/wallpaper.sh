#!/usr/bin/env bash

# Set or rotate the wallpaper, then recolour everything from it.
#
# This used to be three tools and a daemon: waypaper to pick an image,
# wallust-hyprpaper-sync.sh polling hyprpaper for the change, and
# apply-wallust-theme.sh to regenerate the colours. Doing it by hand meant the
# colour regeneration could be missed, and a missed regeneration is invisible -
# the rice just keeps the colours of a wallpaper that is no longer there.
#
# The colour cache in apply-wallust-theme.sh is reused, so re-applying a
# wallpaper you have already used does not regenerate anything.

ACTION="${1:-help}"
WALLPAPER="${2:-}"

case "$ACTION" in

    set)

        [[ -z "$WALLPAPER" ]] && {
            hyprx_ui_error "No wallpaper given."
            hyprx_ui_info "Usage: hyprx wallpaper set <path>"
            exit 1
        }

        if [[ ! -f "$WALLPAPER" ]]; then
            hyprx_ui_error "No such file: $WALLPAPER"
            exit 1
       

        fi

        # Absolute path: a relative one would break the moment the daemon or a
        # later run resolves it from a different working directory.
        if [[ "$WALLPAPER" != /* ]]; then
            WALLPAPER="$PWD/$WALLPAPER"
        fi

        hyprx_ui_section "Setting wallpaper"

        if ! hyprx_util_command_exists hyprpaper; then
            hyprx_ui_error "hyprpaper is not installed - nothing to set a wallpaper with."
            exit 1
        fi

        hyprx_ui_info "Applying $WALLPAPER"
        hyprctl hyprpaper wallpaper "$WALLPAPER" >/dev/null 2>&1 || {
            hyprx_ui_error "hyprctl could not set the wallpaper."
            exit 1
        }

        # Regenerate now rather than waiting for the sync daemon to notice. The
        # daemon polls every 2s, which is fine for a change you did not make
        # yourself and wrong for one you just asked for.
        hyprx_wallpaper_apply_colours "$WALLPAPER"

        hyprx_ui_success "Wallpaper set."
        ;;

    next|rotate)

        hyprx_ui_section "Next wallpaper"

        DIR="${HYPRX_WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
        if [[ ! -d "$DIR" ]]; then
            hyprx_ui_error "No wallpaper folder: $DIR"
            hyprx_ui_info "Set HYPRX_WALLPAPER_DIR_OVERRIDE to point at one."
            exit 1
        fi

        # The last one applied, so "next" means the one after it. Read from the
        # state file the restore script maintains rather than asking hyprpaper,
        # which reports what it was told and not what actually took effect.
        LAST="$(cat "$HYPRX_STATE_WALLPAPER_FILE" 2>/dev/null || true)"

        NEXT=""
        while IFS= read -r candidate; do
            [[ -z "$candidate" ]] && continue
            if [[ -z "$LAST" || "$candidate" > "$LAST" ]]; then
                NEXT="$candidate"
                break
            fi
        done < <(find "$DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \
                -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) -printf '%f\n' 2>/dev/null | sort)

        # Wrapped past the end, or nothing after the last one: start over.
        if [[ -z "$NEXT" ]]; then
            NEXT="$(find "$DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \
                    -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) -printf '%f\n' 2>/dev/null \
                    | sort | head -n1)"
        fi

        if [[ -z "$NEXT" ]]; then
            hyprx_ui_error "No images in $DIR"
            exit 1
        fi

        hyprx wallpaper set "$DIR/$NEXT"
        ;;

    current)

        if hyprx_wallpaper_active >/dev/null 2>&1; then
            hyprx_wallpaper_active
        else
            hyprx_ui_info "No wallpaper is set."
            exit 1
        fi
        ;;

    ""|help|-h|--help)

        hyprx_ui_section "Wallpaper"

        cat <<'EOF'
Usage:
    hyprx wallpaper set <path>   Apply a wallpaper and recolour everything
    hyprx wallpaper next         Advance to the next image in the wallpaper folder
    hyprx wallpaper current      Print the wallpaper that is actually live

The wallpaper folder is ~/Pictures/Wallpapers, or HYPRX_WALLPAPER_DIR_OVERRIDE.
Colours are cached per wallpaper, so re-applying one you have already used
does not regenerate them.
EOF
        ;;

    *)

        hyprx_ui_error "Unknown action: $ACTION"
        hyprx_ui_info "Use 'hyprx wallpaper help'."
        exit 1
        ;;

esac
