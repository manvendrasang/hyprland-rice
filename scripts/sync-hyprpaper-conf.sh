#!/usr/bin/env bash
# Point hyprpaper.conf at a wallpaper that actually exists
#
# hyprpaper re-reads ~/.config/hypr/hyprpaper.conf at every start. waypaper sets wallpapers over
# hyprpaper's IPC and never writes it, so the conf drifts and a restart comes up with nothing.

set -uo pipefail

WALLPAPER="${1:-}"
CONF="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr/hyprpaper.conf"

# Nothing to do without a usable path.
[[ -n "$WALLPAPER" && -f "$WALLPAPER" ]] || exit 0

# Already correct - do not churn the file (this runs on every wallpaper change).
if [[ -f "$CONF" ]] && grep -qF "path = $WALLPAPER" "$CONF" 2>/dev/null; then
    exit 0
fi

mkdir -p "$(dirname "$CONF")" 2>/dev/null || exit 0

tmp="$(mktemp "${CONF}.XXXXXX" 2>/dev/null)" || exit 0

cat >"$tmp" <<EOF
# Written by scripts/sync-hyprpaper-conf.sh to match the active wallpaper.
# Do not hand-edit the path - it is rewritten whenever the wallpaper changes.
wallpaper {
    monitor =
    path = $WALLPAPER
    fit_mode = cover
}

ipc = true
EOF

# Replace atomically so a hyprpaper restart mid-write never reads a truncated
# file (which would leave it with no wallpaper at all).
mv "$tmp" "$CONF" 2>/dev/null || rm -f "$tmp"

exit 0
