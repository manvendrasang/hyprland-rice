#!/usr/bin/env bash

# Machine-readable event stream for GUI frontends (Phase 0 of the visual GUI).
#
# Every event is one JSON object per line on stderr, prefixed with
# HYPRX_EVENT so a frontend can split them from human logs:
#
#   HYPRX_EVENT {"v":1,"ts":1699999999,"mode":"live","type":"package.installed","name":"waybar"}
#
# DESIGN DECISIONS, all deliberate:
#
# - stderr, not stdout. stdout is reserved for what a command produces
#   (`doctor --json` emits a document there; `wallpaper current` a path).
#   The doctor-stdout-corruption bug is why this is a rule and not a habit.
# - Human output is untouched. A frontend reads stderr, keeps lines starting
#   with the prefix as the animation feed, and keeps the rest as the "show
#   log" trapdoor - so beauty never hides truth.
# - `mode` is "live" or "dry-run". A dry run emits the same types with
#   mode=dry-run, which is exactly what a GUI preview needs: the same parser
#   renders "would happen" styling without a second schema.
# - Every mutating command ends with run.completed{rc}. The rc is what a
#   Phase-2 failure visual keys on (red on non-zero), and every failed item
#   emits its own *.failed event first - so a red screen always names names.
# - Schema version "v". A frontend parses v=1 and rejects anything else loudly
#   rather than misrendering a future schema.
#
# `hyprx <cmd> --events` sets HYPRX_EVENTS=1 (extracted globally in
# bin/hyprx, so no per-command parser needs to learn the flag).

HYPRX_EVENT_PREFIX="HYPRX_EVENT "
HYPRX_EVENT_SCHEMA=1

hyprx_events_enabled() {
    [[ "${HYPRX_EVENTS:-0}" == "1" ]]
}

# JSON-escape one string value. Keys are always caller-controlled identifiers;
# values can be paths, reasons and log fragments, so quote, backslash and
# control characters are all escaped. Anything else passes through untouched -
# UTF-8 needs no escaping for a JSON parser.
hyprx_event_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# hyprx_event <type> [key=value ...]
# All values are emitted as strings except v/ts (numbers). Values with no '='
# are dropped rather than mis-split - a malformed pair must not corrupt the
# stream position of every event after it.
hyprx_event() {
    hyprx_events_enabled || return 0

    local type="$1"
    shift || true

    local mode="live"
    hyprx_util_dry_run && mode="dry-run"

    local out
    out="{\"v\":$HYPRX_EVENT_SCHEMA,\"ts\":$(date +%s),\"mode\":\"$mode\",\"type\":\"$(hyprx_event_escape "$type")\""
    local pair key value
    for pair in "$@"; do
        [[ "$pair" == *"="* ]] || continue
        key="${pair%%=*}"
        value="${pair#*=}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        out="$out,\"$key\":\"$(hyprx_event_escape "$value")\""
    done
    out="$out}"

    printf '%s%s\n' "$HYPRX_EVENT_PREFIX" "$out" >&2
    return 0
}
