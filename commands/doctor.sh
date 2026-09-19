#!/usr/bin/env bash

########################################
# Result tally (for the Summary at the
# end / the process exit code). Only
# checks that reflect actual system
# health are wrapped with these - the
# Applications section below is a plain
# presence report, not a health signal,
# so it intentionally still uses the
# bare success/error from lib/ui.sh.
########################################

DOCTOR_WARNINGS=0
DOCTOR_ERRORS=0

note_ok() {
    success "$1"
}

note_warn() {
    warn "$1"
    DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
}

note_err() {
    error "$1"
    DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
}

########################################
# Helpers
########################################

# Validates a JSON/JSONC file. Strips // line comments first since
# jq/json.loads only accept strict JSON - this is a lightweight check,
# not a full JSONC parser, so a "//" inside a quoted string (e.g. a
# URL) can produce a false positive. Good enough for a health check;
# not a substitute for a real linter.
validate_json_file() {

    local file="$1"
    local validator="$2"

    case "$validator" in
        jq)
            sed 's#//.*##' "$file" | jq empty >/dev/null 2>&1
            ;;
        python3)
            python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r"//.*", "", text)
json.loads(text)
' "$file" >/dev/null 2>&1
            ;;
        *)
            return 2
            ;;
    esac

}

# Runs `systemctl [scope] --failed` and reports it, without falsely
# claiming "no failed units" if systemctl itself couldn't be reached
# (e.g. no bus, no systemd) - the original check here treated a
# connection failure the same as "nothing failed".
check_failed_units() {

    local scope="$1"
    local label="$2"
    local output

    if ! output=$(systemctl "$scope" --failed --no-legend 2>&1); then
        info "$label: unable to query (systemctl unavailable or bus unreachable)"
        return
    fi

    if [[ -n "$(echo "$output" | tr -d '[:space:]')" ]]; then
        note_warn "$label: failed units detected"
        echo "$output"
    else
        note_ok "$label: no failed units"
    fi

}

# Everything below is wrapped in one function so a single run can be
# piped to both the terminal and a saved report file (see the very
# bottom of this script) without restructuring every section.
run_doctor_checks() {

header
info_log "Running doctor"

echo

########################################
# Configuration
########################################

section "Configuration"

table_header
table_row "Theme"          "${THEME:-Default}"
table_row "Terminal"       "${TERMINAL:-Unknown}"
table_row "Browser"        "${BROWSER:-Unknown}"
table_row "Editor"         "${EDITOR:-Unknown}"
table_row "File Manager"   "${FILE_MANAGER:-Unknown}"
table_row "Launcher"       "${LAUNCHER:-Unknown}"

echo

########################################
# Applications
#
# Presence-only. Missing an optional app
# (e.g. Neovim) isn't a health problem,
# so this does NOT feed the Summary tally.
########################################

section "Applications"

check() {

    local name="$1"
    local status="$2"

    if [[ "$status" == true ]]; then
        success "$name"
    else
        error "$name"
    fi

}

check "Hyprland Installed" "$HAS_HYPRLAND"
check "Waybar Installed" "$HAS_WAYBAR"
check "Rofi Installed" "$HAS_ROFI"
check "Kitty Installed" "$HAS_KITTY"
check "VS Code Installed" "$HAS_CODE"
check "Neovim Installed" "$HAS_NVIM"
check "Git Installed" "$HAS_GIT"
check "SwayNC Installed" "$HAS_SWAYNC"
check "PipeWire Installed" "$HAS_PIPEWIRE"
check "Bluetooth Installed" "$HAS_BLUETOOTH"

echo

########################################
# System Information
########################################

section "System Information"

table_header
table_row "Distribution"       "$DISTRO_NAME"
table_row "Package Manager"    "$PACKAGE_MANAGER"
table_row "CPU Vendor"         "$CPU_VENDOR"
table_row "GPU Vendor"         "$GPU_VENDOR"
table_row "Battery"            "${BATTERY_NAME:-None}"
table_row "Network Interface"  "${NETWORK_INTERFACE:-Unknown}"
table_row "ZRAM"               "$HAS_ZRAM"
table_row "Power Profiles"     "$HAS_POWER_PROFILE"

echo

########################################
# Config Validation
#
# Catches the exact class of bug that put
# swaync into a crash-loop: broken JSON in
# a deployed config, silently killing the
# service that reads it.
########################################

section "Config Validation"

json_validator=""
if command_exists jq; then
    json_validator="jq"
elif command_exists python3; then
    json_validator="python3"
fi

if [[ -z "$json_validator" ]]; then
    info "No JSON validator available (jq or python3) - skipping"
else
    found_json=false
    for cfgdir in $HYPRX_CONFIG_TARGETS; do
        target_dir="${HYPRX_TARGET_HOME:-$HOME}/.config/$cfgdir"
        [[ -d "$target_dir" ]] || continue
        while IFS= read -r -d '' f; do
            found_json=true
            display="${f/#$HOME/~}"
            if [[ ! -s "$f" ]]; then
                info "Empty (unused stub, not referenced by config.jsonc): $display"
                continue
            fi
            if validate_json_file "$f" "$json_validator"; then
                note_ok "Valid JSON: $display"
            else
                note_err "Invalid JSON: $display (this will crash-loop whatever reads it)"
            fi
        done < <(find "$target_dir" -type f \( -name "*.json" -o -name "*.jsonc" \) -print0 2>/dev/null)
    done
    [[ "$found_json" == false ]] && info "No deployed JSON/JSONC config files found"
fi

# hyprland.lua and hyprlock.conf aren't JSON, so they need their own
# checks - added after a session where a broken sed edit to
# hyprland.lua silently corrupted a line (no crash, no error until
# the next reload/restart tried to use it).
lua_checker=""
for candidate in luac luac5.4 luac5.3 luac5.1; do
    if command_exists "$candidate"; then
        lua_checker="$candidate"
        break
    fi
done

hyprland_lua="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr/hyprland.lua"
if [[ -f "$hyprland_lua" ]]; then
    if [[ -n "$lua_checker" ]]; then
        if "$lua_checker" -p "$hyprland_lua" >/dev/null 2>&1; then
            note_ok "hyprland.lua: valid Lua syntax"
        else
            note_err "hyprland.lua: Lua syntax error - a reload or session restart will fail to pick up recent edits. Run: $lua_checker -p ~/.config/hypr/hyprland.lua for details"
        fi
    else
        info "No Lua syntax checker (luac) available - skipping hyprland.lua check"
    fi
else
    info "hyprland.lua not found, skipping"
fi

# Not a real hyprlang parser, just a balanced-braces check - cheap,
# but catches an obviously malformed file (a missing/extra brace from
# a bad manual edit) without needing any extra tooling.
hyprlock_conf="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr/hyprlock.conf"
if [[ -f "$hyprlock_conf" ]]; then
    open_braces=$(grep -o '{' "$hyprlock_conf" 2>/dev/null | wc -l || true)
    close_braces=$(grep -o '}' "$hyprlock_conf" 2>/dev/null | wc -l || true)
    if [[ "$open_braces" == "$close_braces" ]]; then
        note_ok "hyprlock.conf: braces balanced ($open_braces pairs)"
    else
        note_err "hyprlock.conf: unbalanced braces ($open_braces open, $close_braces close) - hyprlock will fail to start or misparse a block"
    fi
else
    info "hyprlock.conf not found, skipping"
fi

echo

########################################
# Config Deployment Drift
########################################

section "Config Deployment Drift"

for cfgdir in $HYPRX_CONFIG_TARGETS; do

    repo_dir="$HYPRX_CONFIG/$cfgdir"
    target_dir="${HYPRX_TARGET_HOME:-$HOME}/.config/$cfgdir"

    if [[ ! -d "$target_dir" ]]; then
        note_warn "$cfgdir: not deployed (missing from ~/.config)"
        continue
    fi

    if [[ ! -d "$repo_dir" ]]; then
        info "$cfgdir: deployed, but no longer tracked in the repo"
        continue
    fi

    diff_output=$(diff -rq "$repo_dir" "$target_dir" 2>/dev/null || true)

    if [[ -z "$diff_output" ]]; then
        note_ok "$cfgdir: matches repo"
    else
        diff_count=$(printf '%s\n' "$diff_output" | grep -c .)
        note_warn "$cfgdir: $diff_count file(s) differ from repo (locally edited, or repo updated since last deploy)"
    fi

done

echo

########################################
# Storage
########################################

section "Storage"

root_usage="$(df -h / | awk 'NR==2 {print $5}')"

table_header
table_row "Root Usage" "$root_usage"

echo

########################################
# Memory
########################################

section "Memory"

free -h

mem_total=$(free -b | awk '/^Mem:/ {print $2}')
mem_avail=$(free -b | awk '/^Mem:/ {print $7}')

if [[ -n "$mem_avail" ]]; then
    if (( mem_avail < 536870912 )); then
        note_err "Critically low available memory: $(bytes_to_human "$mem_avail") of $(bytes_to_human "$mem_total") total"
    elif (( mem_avail < 1073741824 )); then
        note_warn "Low available memory: $(bytes_to_human "$mem_avail") of $(bytes_to_human "$mem_total") total"
    else
        note_ok "Available memory: $(bytes_to_human "$mem_avail") of $(bytes_to_human "$mem_total") total"
    fi
fi

echo

########################################
# Swap
########################################

section "Swap"

swapon --show || true

swap_total=$(free -b | awk '/^Swap:/ {print $2}')
swap_used=$(free -b | awk '/^Swap:/ {print $3}')

if [[ -n "$swap_total" && "$swap_total" -gt 0 ]]; then
    swap_pct=$(( swap_used * 100 / swap_total ))
    if (( swap_pct >= 80 )); then
        note_warn "Swap heavily utilized: ${swap_pct}% used - may indicate memory pressure"
    elif (( swap_pct >= 50 )); then
        info "Swap moderately used: ${swap_pct}%"
    else
        note_ok "Swap usage normal: ${swap_pct}%"
    fi
else
    info "No swap configured"
fi

echo

########################################
# Systemd - System & User Services
########################################

section "Systemd"

check_failed_units "" "System services"
echo
check_failed_units "--user" "User services"

echo

########################################
# HyprX Managed Services
#
# Enforces services.list - flags anything
# HyprX expects enabled that isn't. This
# is what would have caught supergfxd
# never being enabled on this machine.
########################################

section "HyprX Managed Services"

services_file="$HYPRX_ROOT/services.list"

if [[ -f "$services_file" ]]; then
    while IFS= read -r line; do

        svc="${line%%#*}"
        svc="$(echo "$svc" | xargs)"
        [[ -z "$svc" ]] && continue

        if ! systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q .; then
            info "$svc: not installed (no unit file found)"
            continue
        fi

        state=$(systemctl is-enabled "${svc}.service" 2>/dev/null || true)

        case "$state" in
            enabled|static|enabled-runtime|alias)
                note_ok "$svc ($state)"
                ;;
            *)
                note_warn "$svc installed but not enabled (state: ${state:-unknown})"
                ;;
        esac

    done < "$services_file"
else
    info "services.list not found, skipping"
fi

echo

########################################
# Session Health
#
# Everything in this section checks LIVE
# runtime state (is a daemon not just
# running, but actually doing its job)
# rather than static config - added after
# a session where hyprpaper stayed alive
# with no active wallpaper layer, and
# waybar silently failed to launch, with
# neither condition visible from process
# lists or config files alone.
########################################

section "Session Health"

if command_exists hyprctl && pgrep -x Hyprland >/dev/null 2>&1; then

    layers_out=$(hyprctl layers 2>/dev/null || true)

    # hyprpaper
    if pgrep -x hyprpaper >/dev/null 2>&1; then
        if echo "$layers_out" | grep -q "namespace: hyprpaper"; then
            note_ok "hyprpaper running with an active background layer"
        else
            note_warn "hyprpaper is running but has no active background layer (no wallpaper set) - try: ~/.local/share/hyprx/scripts/wallpaper-restore.sh"
        fi
    else
        note_warn "hyprpaper is not running"
    fi

    # waybar
    if pgrep -x waybar >/dev/null 2>&1; then
        if echo "$layers_out" | grep -q "namespace: waybar"; then
            note_ok "waybar running with an active layer"
        else
            note_warn "waybar process is running but has no registered layer - may still be starting, or crashed after initial launch"
        fi
    else
        note_warn "waybar is not running"
    fi

    # Live GBM/render backend, read from the actual running Hyprland
    # process - not the config file, which can say one thing while a
    # stale/different value is what's actually active this session.
    hypr_pid=$(pgrep -x Hyprland | head -1)
    gbm_backend=$(tr '\0' '\n' < "/proc/$hypr_pid/environ" 2>/dev/null | grep '^GBM_BACKEND=' | cut -d= -f2)
    if [[ "$gbm_backend" == "nvidia-drm" ]]; then
        note_warn "GBM_BACKEND=nvidia-drm is active in the live Hyprland process - on a MUX-less hybrid laptop this can leave the panel blank (Hyprland renders correctly, but nothing reaches the screen). See the comment above this setting in config/hypr/hyprland.lua."
    elif [[ -n "$gbm_backend" ]]; then
        info "GBM_BACKEND=$gbm_backend active in the live Hyprland process"
    else
        note_ok "No GBM_BACKEND override active (auto-detect)"
    fi

else
    info "Hyprland/hyprctl not available, skipping session health checks"
fi

echo

########################################
# Hybrid GPU
#
# Only runs on machines with supergfxd
# tooling present - skipped entirely on
# single-GPU systems.
########################################

if command_exists supergfxctl; then

    section "Hybrid GPU"

    if systemctl is-active --quiet supergfxd 2>/dev/null; then
        note_ok "supergfxd active"
    else
        note_err "supergfxd installed but not running - dGPU cannot power-manage or PRIME offload correctly"
    fi

    gfx_mode=$(supergfxctl -g 2>/dev/null || echo "unknown")
    info "Graphics mode: $gfx_mode"

    modeset_file="/sys/module/nvidia_drm/parameters/modeset"
    if [[ -f "$modeset_file" ]]; then
        modeset_val=$(cat "$modeset_file" 2>/dev/null || echo "?")
        if [[ "$modeset_val" == "Y" ]]; then
            note_ok "nvidia_drm.modeset enabled"
        else
            note_warn "nvidia_drm.modeset is not enabled (currently: $modeset_val) - PRIME render offload will not work"
        fi
    else
        info "nvidia_drm module not loaded"
    fi

    nvidia_pci=$(lspci -d 10de: -D 2>/dev/null | awk '{print $1; exit}' || true)
    if [[ -n "$nvidia_pci" ]]; then
        runtime_status_file="/sys/bus/pci/devices/$nvidia_pci/power/runtime_status"
        if [[ -f "$runtime_status_file" ]]; then
            info "dGPU runtime PM status: $(cat "$runtime_status_file" 2>/dev/null || echo unknown)"
        fi
    fi

    echo

fi

########################################
# Network & Radios
########################################

section "Network & Radios"

if command_exists rfkill; then
    rfkill_out=$(rfkill list 2>/dev/null)
    if echo "$rfkill_out" | grep -qi "blocked: yes"; then
        note_warn "One or more radios are soft/hard blocked:"
        echo "$rfkill_out" | grep -B2 -i "blocked: yes"
    else
        note_ok "No radios blocked (bluetooth/wifi/etc all unblocked)"
    fi
else
    info "rfkill not available, skipping radio block check"
fi

if command_exists nmcli; then
    conn_state=$(nmcli -t -f STATE general status 2>/dev/null)
    if [[ "$conn_state" == "connected" ]]; then
        note_ok "NetworkManager: connected"
    elif [[ -n "$conn_state" ]]; then
        note_warn "NetworkManager state: $conn_state (not fully connected)"
    else
        info "Could not query NetworkManager state"
    fi
else
    info "nmcli not available, skipping network state check"
fi

echo

########################################
# Pacman
########################################

section "Pacman"

if command_exists pacman; then

    if [[ -f /var/lib/pacman/db.lck ]]; then
        note_warn "Pacman database is locked"
    else
        note_ok "Pacman database unlocked"
    fi

    pacnew_count=$(find /etc -xdev -name "*.pacnew" 2>/dev/null | wc -l | tr -d ' ')
    if (( pacnew_count > 0 )); then
        note_warn "$pacnew_count .pacnew file(s) found under /etc - review with pacdiff"
    else
        note_ok "No .pacnew files found"
    fi

    orphan_count=$(pacman -Qdtq 2>/dev/null | grep -c . || true)
    if (( orphan_count > 0 )); then
        note_warn "$orphan_count orphaned package(s) - remove with: pacman -Rns \$(pacman -Qdtq)"
    else
        note_ok "No orphaned packages"
    fi

else
    info "pacman not available, skipping Pacman checks"
fi

echo

########################################
# Summary
########################################

section "Summary"

if (( DOCTOR_ERRORS > 0 )); then
    error "$DOCTOR_ERRORS error(s), $DOCTOR_WARNINGS warning(s) found - see above"
    error_log "Doctor finished: $DOCTOR_ERRORS errors, $DOCTOR_WARNINGS warnings"
    exit 2
elif (( DOCTOR_WARNINGS > 0 )); then
    warn "$DOCTOR_WARNINGS warning(s) found, no errors"
    warn_log "Doctor finished: 0 errors, $DOCTOR_WARNINGS warnings"
    exit 1
else
    success "All checks passed"
    success_log "Doctor finished clean"
fi

}

########################################
# Run + save a report
#
# Every run is saved as a timestamped,
# color-stripped log under
# ~/.local/state/hyprx/reports/, so a
# single `hyprx doctor` run produces a
# durable diagnostic document - not just
# terminal output that scrolls away.
########################################

REPORT_DIR="$HOME/.local/state/hyprx/reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/doctor-$(date +%Y%m%d-%H%M%S).log"

run_doctor_checks 2>&1 | tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$REPORT_FILE")
DOCTOR_EXIT="${PIPESTATUS[0]}"

echo
info "Full report saved to: $REPORT_FILE"

exit "$DOCTOR_EXIT"
