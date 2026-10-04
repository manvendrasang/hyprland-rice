#!/usr/bin/env bash
# Triggered by scripts/wallust-hyprpaper-sync.sh on every wallpaper change:
# applies the templated colours, then reloads only the long-running daemons.
#
# COLOUR MEMORY
# -------------
# wallust extracts a palette from the wallpaper image on every run. That is the
# expensive part, and this script used to pay it on every single wallpaper
# change - including the ones that arrive within seconds of each other while
# browsing, and the one at every login. For a wallpaper that has already been
# seen the answer cannot change, so it is remembered.
#
# The cache key covers everything that can change the result:
#   - the wallpaper path, size and mtime
#   - wallust.toml (targets, filters)
#   - every file in the templates directory
# Editing a template therefore misses the cache and regenerates, rather than
# silently serving colours that no longer match what wallust would produce.
#
# What is stored is the rendered output files, not a palette, so a hit needs no
# template rendering at all - it is a copy.

set -uo pipefail

WALLPAPER="${1:-}"

if [[ -z "$WALLPAPER" ]]; then
    exit 0
fi

command -v wallust >/dev/null 2>&1 || exit 0

LOG_FILE="${HYPRX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx}/hyprx.log"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/hyprx/wallust"
CACHE_KEEP="${HYPRX_WALLUST_CACHE_KEEP:-12}"

log() {
    printf '[apply-wallust-theme] %s\n' "$*" >&2
    printf '[%s] [INFO] apply-wallust-theme: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

WALLUST_TOML="$HOME/.config/wallust/wallust.toml"
TEMPLATES_DIR="$HOME/.config/wallust/templates"

# The targets come from the deployed wallust.toml rather than a hardcoded list,
# so a template added or retargeted there is picked up without editing this.
mapfile -t RAW_TARGETS < <(
    sed -n 's/^[[:space:]]*[A-Za-z0-9_.-]*\.target[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
        "$WALLUST_TOML" 2>/dev/null
)

TARGETS=()
for t in "${RAW_TARGETS[@]}"; do
    [[ -n "$t" ]] && TARGETS+=("${t/#\~/$HOME}")
done

# One fingerprint over every input that can change the output.
fingerprint() {
    {
        printf 'wallpaper\t%s\n' "$WALLPAPER"
        stat -c 'stat\t%s\t%Y' "$WALLPAPER" 2>/dev/null || printf 'stat\tmissing\n'
        if [[ -f "$WALLUST_TOML" ]]; then
            printf 'toml\t%s\n' "$(sha256sum "$WALLUST_TOML" | cut -d' ' -f1)"
        fi
        if [[ -d "$TEMPLATES_DIR" ]]; then
            while IFS= read -r f; do
                printf 'tpl\t%s\t%s\n' "$(basename "$f")" \
                    "$(sha256sum "$f" | cut -d' ' -f1)"
            done < <(find "$TEMPLATES_DIR" -type f | sort)
        fi
    } | sha256sum | cut -d' ' -f1
}

# True only if every target has a stored copy. A partial hit is a miss: serving
# half a palette is worse than recomputing it.
cache_complete() {
    local entry="$1" dest
    (( ${#TARGETS[@]} > 0 )) || return 1
    for dest in "${TARGETS[@]}"; do
        [[ -f "$entry/files/${dest#"$HOME"/}" ]] || return 1
    done
    return 0
}

prune_cache() {
    local keep="$1" dir
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && rm -rf "$dir"
    done < <(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null \
                | sort -rn | tail -n "+$((keep + 1))" | cut -f2-)
}

CACHE_KEY="$(fingerprint)"
CACHE_ENTRY="$CACHE_ROOT/$CACHE_KEY"

if cache_complete "$CACHE_ENTRY"; then
    log "colour cache hit for $(basename "$WALLPAPER") - not regenerating"
    for dest in "${TARGETS[@]}"; do
        mkdir -p "$(dirname "$dest")"
        cp "$CACHE_ENTRY/files/${dest#"$HOME"/}" "$dest" || true
    done
else
    log "colour cache miss for $(basename "$WALLPAPER") - running wallust"
    wallust run "$WALLPAPER" --quiet --check-contrast

    rm -rf "$CACHE_ENTRY"
    for dest in "${TARGETS[@]}"; do
        [[ -f "$dest" ]] || continue
        mkdir -p "$CACHE_ENTRY/files/$(dirname "${dest#"$HOME"/}")"
        cp "$dest" "$CACHE_ENTRY/files/${dest#"$HOME"/}"
    done
    prune_cache "$CACHE_KEEP"
fi

# Keep hyprpaper.conf pointing at the wallpaper that is actually live.
# Runs on every wallpaper change, not just at login: waypaper never updates
# hyprpaper.conf, so without this the conf drifts to a stale path and the next
# hyprpaper restart reverts the wallpaper or comes up with nothing at all.
HYPRX_SYNC_CONF="${HYPRX_TARGET_HOME:-$HOME}/.local/share/hyprx/scripts/sync-hyprpaper-conf.sh"
# if/then rather than `[[ -x … ]] && "$…" || true`. The &&/|| form is not
# if-then-else: the trailing `|| true` is a third statement that runs whenever the
# sync script itself fails, so a sync failure and a missing script are
# indistinguishable - and neither was reported. Here both are handled, and the
# sync failure is visible in the log instead of vanishing.
if [[ -x "$HYPRX_SYNC_CONF" ]]; then
    if ! "$HYPRX_SYNC_CONF" "$WALLPAPER"; then
        echo "apply-wallust-theme: could not sync hyprpaper.conf" >&2
    fi
else
    echo "apply-wallust-theme: $HYPRX_SYNC_CONF is missing or not executable" >&2
fi

# Waybar only reads colors.css at (re)start.
~/.local/share/hyprx/scripts/reload-waybar.sh >/dev/null 2>&1 &

# swaync supports a live CSS reload without losing notification history.
if command -v swaync-client >/dev/null 2>&1; then
    swaync-client --reload-css >/dev/null 2>&1 &
fi

# Hyprland's border colors are read via require("colors") at config
# parse time, so they need a full reload to pick up the new file.
if command -v hyprctl >/dev/null 2>&1; then
    ~/.local/share/hyprx/scripts/reload-hypr.sh >/dev/null 2>&1 &
fi

wait