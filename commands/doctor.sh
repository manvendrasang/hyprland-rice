#!/usr/bin/env bash

########################################
# Result tally (for the Summary at the
# end / the process exit code). Only
# checks that reflect actual system
# health are wrapped with these - the
# Applications section below is a plain
# presence report, not a health signal,
# so it intentionally still uses the
# bare hyprx_ui_success/hyprx_ui_error
# from lib/ui.sh.
########################################

DOCTOR_WARNINGS=0
DOCTOR_ERRORS=0

hyprx_doctor_note_ok() {
    hyprx_ui_success "$1"
}

hyprx_doctor_note_warn() {
    hyprx_ui_warn "$1"
    DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
}

hyprx_doctor_note_err() {
    hyprx_ui_error "$1"
    DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
}

########################################
# Helpers
########################################

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

check_failed_units() {

    local scope="$1"
    local label="$2"
    local output
    local -a systemctl_args=()

    [[ -n "$scope" ]] && systemctl_args+=("$scope")

    if ! output=$(systemctl "${systemctl_args[@]}" --failed --no-legend 2>&1); then
        hyprx_ui_info "$label: unable to query (systemctl unavailable or bus unreachable)"
        return
    fi

    if [[ -n "$(echo "$output" | tr -d '[:space:]')" ]]; then
        hyprx_doctor_note_warn "$label: failed units detected"
        echo "$output"
    else
        hyprx_doctor_note_ok "$label: no failed units"
    fi

}

run_doctor_checks() {

hyprx_ui_header
hyprx_logger_info "Running doctor"

echo

########################################
# Configuration
########################################

hyprx_ui_section "Configuration"

hyprx_table_header
hyprx_table_row "Theme"          "${HYPRX_CONFIG_THEME:-Default}"
hyprx_table_row "Terminal"       "${TERMINAL:-Unknown}"
hyprx_table_row "Browser"        "${BROWSER:-Unknown}"
hyprx_table_row "Editor"         "${EDITOR:-Unknown}"
hyprx_table_row "File Manager"   "${FILE_MANAGER:-Unknown}"
hyprx_table_row "Launcher"       "${LAUNCHER:-Unknown}"

echo

########################################
# Applications
########################################

hyprx_ui_section "Applications"

check() {

    local name="$1"
    local status="$2"

    if [[ "$status" == true ]]; then
        hyprx_ui_success "$name"
    else
        hyprx_ui_error "$name"
    fi

}

check "Hyprland Installed" "$HYPRX_DETECT_HAS_HYPRLAND"
check "Waybar Installed" "$HYPRX_DETECT_HAS_WAYBAR"
check "Rofi Installed" "$HYPRX_DETECT_HAS_ROFI"
check "Kitty Installed" "$HYPRX_DETECT_HAS_KITTY"
check "VS Code Installed" "$HYPRX_DETECT_HAS_CODE"
check "Neovim Installed" "$HYPRX_DETECT_HAS_NVIM"
check "Git Installed" "$HYPRX_DETECT_HAS_GIT"
check "SwayNC Installed" "$HYPRX_DETECT_HAS_SWAYNC"
check "PipeWire Installed" "$HYPRX_DETECT_HAS_PIPEWIRE"
check "Bluetooth Installed" "$HYPRX_DETECT_HAS_BLUETOOTH"

echo

########################################
# System Information
########################################

hyprx_ui_section "System Information"

hyprx_table_header
hyprx_table_row "Distribution"       "$HYPRX_DETECT_DISTRO_NAME"
hyprx_table_row "Package Manager"    "$HYPRX_DETECT_PACKAGE_MANAGER"
hyprx_table_row "CPU Vendor"         "$HYPRX_DETECT_CPU_VENDOR"
hyprx_table_row "GPU Vendor"         "$HYPRX_DETECT_GPU_VENDOR"
hyprx_table_row "Battery"            "${HYPRX_DETECT_BATTERY_NAME:-None}"
hyprx_table_row "Network Interface"  "${HYPRX_DETECT_NETWORK_INTERFACE:-Unknown}"
hyprx_table_row "ZRAM"               "$HYPRX_DETECT_HAS_ZRAM"
hyprx_table_row "Power Profiles"     "$HYPRX_DETECT_HAS_POWER_PROFILE"

echo

########################################
# Config Validation
########################################

hyprx_ui_section "Config Validation"

json_validator=""
if hyprx_util_command_exists jq; then
    json_validator="jq"
elif hyprx_util_command_exists python3; then
    json_validator="python3"
fi

if [[ -z "$json_validator" ]]; then
    hyprx_ui_info "No JSON validator available (jq or python3) - skipping"
else
    found_json=false
    for cfgdir in $HYPRX_CONFIG_TARGETS; do
        target_dir="${HYPRX_TARGET_HOME:-$HOME}/.config/$cfgdir"
        [[ -d "$target_dir" ]] || continue
        while IFS= read -r -d '' f; do
            found_json=true
            display="${f/#$HOME/~}"
            if [[ ! -s "$f" ]]; then
                hyprx_ui_info "Empty (unused stub, not referenced by config.jsonc): $display"
                continue
            fi
            if validate_json_file "$f" "$json_validator"; then
                hyprx_doctor_note_ok "Valid JSON: $display"
            else
                hyprx_doctor_note_err "Invalid JSON: $display (this will crash-loop whatever reads it)"
            fi
        done < <(find "$target_dir" -type f \( -name "*.json" -o -name "*.jsonc" \) -print0 2>/dev/null)
    done
    [[ "$found_json" == false ]] && hyprx_ui_info "No deployed JSON/JSONC config files found"
fi

lua_checker=""
for candidate in luac luac5.4 luac5.3 luac5.1; do
    if hyprx_util_command_exists "$candidate"; then
        lua_checker="$candidate"
        break
    fi
done

hyprland_lua="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr/hyprland.lua"
if [[ -f "$hyprland_lua" ]]; then
    if [[ -n "$lua_checker" ]]; then
        if "$lua_checker" -p "$hyprland_lua" >/dev/null 2>&1; then
            hyprx_doctor_note_ok "hyprland.lua: valid Lua syntax"
        else
            hyprx_doctor_note_err "hyprland.lua: Lua syntax error - a reload or session restart will fail to pick up recent edits. Run: $lua_checker -p ~/.config/hypr/hyprland.lua for details"
        fi
    else
        hyprx_ui_info "No Lua syntax checker (luac) available - skipping hyprland.lua check"
    fi
else
    hyprx_ui_info "hyprland.lua not found, skipping"
fi

hyprlock_conf="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr/hyprlock.conf"
if [[ -f "$hyprlock_conf" ]]; then
    open_braces=$(grep -o '{' "$hyprlock_conf" 2>/dev/null | wc -l || true)
    close_braces=$(grep -o '}' "$hyprlock_conf" 2>/dev/null | wc -l || true)
    if [[ "$open_braces" == "$close_braces" ]]; then
        hyprx_doctor_note_ok "hyprlock.conf: braces balanced ($open_braces pairs)"
    else
        hyprx_doctor_note_err "hyprlock.conf: unbalanced braces ($open_braces open, $close_braces close) - hyprlock will fail to start or misparse a block"
    fi
else
    hyprx_ui_info "hyprlock.conf not found, skipping"
fi

echo

########################################
# Config Deployment Drift
########################################

hyprx_ui_section "Config Deployment Drift"

for cfgdir in $HYPRX_CONFIG_TARGETS; do

    repo_dir="$HYPRX_CONFIG/$cfgdir"
    target_dir="${HYPRX_TARGET_HOME:-$HOME}/.config/$cfgdir"

    if [[ ! -d "$target_dir" ]]; then
        hyprx_doctor_note_warn "$cfgdir: not deployed (missing from ~/.config)"
        continue
    fi

    if [[ ! -d "$repo_dir" ]]; then
        hyprx_ui_info "$cfgdir: deployed, but no longer tracked in the repo"
        continue
    fi

    diff_output=$(diff -rq "$repo_dir" "$target_dir" 2>/dev/null || true)

    if [[ -z "$diff_output" ]]; then
        hyprx_doctor_note_ok "$cfgdir: matches repo"
    else
        diff_count=$(printf '%s\n' "$diff_output" | grep -c .)
        hyprx_doctor_note_warn "$cfgdir: $diff_count file(s) differ from repo (locally edited, or repo updated since last deploy)"
    fi

done

echo

########################################
# Storage
########################################

hyprx_ui_section "Storage"

root_usage="$(df -h / | awk 'NR==2 {print $5}')"

hyprx_table_header
hyprx_table_row "Root Usage" "$root_usage"

echo

########################################
# Memory
########################################

hyprx_ui_section "Memory"

free -h

mem_total=$(free -b | awk '/^Mem:/ {print $2}')
mem_avail=$(free -b | awk '/^Mem:/ {print $7}')

if [[ -n "$mem_avail" ]]; then
    if (( mem_avail < 536870912 )); then
        hyprx_doctor_note_err "Critically low available memory: $(hyprx_util_bytes_to_human "$mem_avail") of $(hyprx_util_bytes_to_human "$mem_total") total"
    elif (( mem_avail < 1073741824 )); then
        hyprx_doctor_note_warn "Low available memory: $(hyprx_util_bytes_to_human "$mem_avail") of $(hyprx_util_bytes_to_human "$mem_total") total"
    else
        hyprx_doctor_note_ok "Available memory: $(hyprx_util_bytes_to_human "$mem_avail") of $(hyprx_util_bytes_to_human "$mem_total") total"
    fi
fi

echo

########################################
# Swap
########################################

hyprx_ui_section "Swap"

swapon --show || true

swap_total=$(free -b | awk '/^Swap:/ {print $2}')
swap_used=$(free -b | awk '/^Swap:/ {print $3}')

if [[ -n "$swap_total" && "$swap_total" -gt 0 ]]; then
    swap_pct=$(( swap_used * 100 / swap_total ))
    if (( swap_pct >= 80 )); then
        hyprx_doctor_note_warn "Swap heavily utilized: ${swap_pct}% used - may indicate memory pressure"
    elif (( swap_pct >= 50 )); then
        hyprx_ui_info "Swap moderately used: ${swap_pct}%"
    else
        hyprx_doctor_note_ok "Swap usage normal: ${swap_pct}%"
    fi
else
    hyprx_ui_info "No swap configured"
fi

echo

########################################
# Systemd - System & User Services
########################################

hyprx_ui_section "Systemd"

check_failed_units "" "System services"
echo
check_failed_units "--user" "User services"

echo

########################################
# HyprX Managed Services
########################################

hyprx_ui_section "HyprX Managed Services"

services_file="$HYPRX_ROOT/services.list"

if [[ -f "$services_file" ]]; then
    while IFS= read -r line; do

        svc="${line%%#*}"
        svc="$(echo "$svc" | xargs)"
        [[ -z "$svc" ]] && continue

        if ! systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q .; then
            hyprx_ui_info "$svc: not installed (no unit file found)"
            continue
        fi

        state=$(systemctl is-enabled "${svc}.service" 2>/dev/null || true)

        case "$state" in
            enabled|static|enabled-runtime|alias)
                hyprx_doctor_note_ok "$svc ($state)"
                ;;
            *)
                hyprx_doctor_note_warn "$svc installed but not enabled (state: ${state:-unknown})"
                ;;
        esac

    done < "$services_file"
else
    hyprx_ui_info "services.list not found, skipping"
fi

echo

########################################
# Session Health
########################################

hyprx_ui_section "Session Health"

if hyprx_util_command_exists hyprctl && pgrep -x Hyprland >/dev/null 2>&1; then

    layers_out=$(hyprctl layers 2>/dev/null || true)

    if pgrep -x hyprpaper >/dev/null 2>&1; then
        if echo "$layers_out" | grep -q "namespace: hyprpaper"; then
            hyprx_doctor_note_ok "hyprpaper running with an active background layer"
        else
            hyprx_doctor_note_warn "hyprpaper is running but has no active background layer (no wallpaper set) - try: ~/.local/share/hyprx/scripts/wallpaper-restore.sh"
        fi
    else
        hyprx_doctor_note_warn "hyprpaper is not running"
    fi

    if pgrep -x waybar >/dev/null 2>&1; then
        if echo "$layers_out" | grep -q "namespace: waybar"; then
            hyprx_doctor_note_ok "waybar running with an active layer"
        else
            hyprx_doctor_note_warn "waybar process is running but has no registered layer - may still be starting, or crashed after initial launch"
        fi
    else
        hyprx_doctor_note_warn "waybar is not running"
    fi

    hypr_pid=$(pgrep -x Hyprland | head -1)
    gbm_backend=$(tr '\0' '\n' < "/proc/$hypr_pid/environ" 2>/dev/null | grep '^GBM_BACKEND=' | cut -d= -f2 || true)
    if [[ "$gbm_backend" == "nvidia-drm" ]]; then
        hyprx_doctor_note_warn "GBM_BACKEND=nvidia-drm is active in the live Hyprland process - on a MUX-less hybrid laptop this can leave the panel blank (Hyprland renders correctly, but nothing reaches the screen). See the comment above this setting in config/hypr/hyprland.lua."
    elif [[ -n "$gbm_backend" ]]; then
        hyprx_ui_info "GBM_BACKEND=$gbm_backend active in the live Hyprland process"
    else
        hyprx_doctor_note_ok "No GBM_BACKEND override active (auto-detect)"
    fi

else
    hyprx_ui_info "Hyprland/hyprctl not available, skipping session health checks"
fi

echo

########################################
# Hybrid GPU
########################################

if hyprx_util_command_exists supergfxctl; then

    hyprx_ui_section "Hybrid GPU"

    if systemctl is-active --quiet supergfxd 2>/dev/null; then
        hyprx_doctor_note_ok "supergfxd active"
    else
        hyprx_doctor_note_err "supergfxd installed but not running - dGPU cannot power-manage or PRIME offload correctly"
    fi

    gfx_mode=$(supergfxctl -g 2>/dev/null || echo "unknown")
    hyprx_ui_info "Graphics mode: $gfx_mode"

    modeset_file="/sys/module/nvidia_drm/parameters/modeset"
    if [[ -f "$modeset_file" ]]; then
        modeset_val=$(cat "$modeset_file" 2>/dev/null || echo "?")
        if [[ "$modeset_val" == "Y" ]]; then
            hyprx_doctor_note_ok "nvidia_drm.modeset enabled"
        else
            hyprx_doctor_note_warn "nvidia_drm.modeset is not enabled (currently: $modeset_val) - PRIME render offload will not work"
        fi
    else
        hyprx_ui_info "nvidia_drm module not loaded"
    fi

    nvidia_pci=$(lspci -d 10de: -D 2>/dev/null | awk '{print $1; exit}' || true)
    if [[ -n "$nvidia_pci" ]]; then
        runtime_status_file="/sys/bus/pci/devices/$nvidia_pci/power/runtime_status"
        if [[ -f "$runtime_status_file" ]]; then
            hyprx_ui_info "dGPU runtime PM status: $(cat "$runtime_status_file" 2>/dev/null || echo unknown)"
        fi
    fi

    echo

fi

########################################
# Network & Radios
########################################

hyprx_ui_section "Network & Radios"

if hyprx_util_command_exists rfkill; then
    rfkill_out=$(rfkill list 2>/dev/null)
    if echo "$rfkill_out" | grep -qi "blocked: yes"; then
        hyprx_doctor_note_warn "One or more radios are soft/hard blocked:"
        echo "$rfkill_out" | grep -B2 -i "blocked: yes"
    else
        hyprx_doctor_note_ok "No radios blocked (bluetooth/wifi/etc all unblocked)"
    fi
else
    hyprx_ui_info "rfkill not available, skipping radio block check"
fi

if hyprx_util_command_exists nmcli; then
    conn_state=$(nmcli -t -f STATE general status 2>/dev/null)
    if [[ "$conn_state" == "connected" ]]; then
        hyprx_doctor_note_ok "NetworkManager: connected"
    elif [[ -n "$conn_state" ]]; then
        hyprx_doctor_note_warn "NetworkManager state: $conn_state (not fully connected)"
    else
        hyprx_ui_info "Could not query NetworkManager state"
    fi
else
    hyprx_ui_info "nmcli not available, skipping network state check"
fi

echo

########################################
# Pacman
########################################

hyprx_ui_section "Pacman"

if hyprx_util_command_exists pacman; then

    if [[ -f /var/lib/pacman/db.lck ]]; then
        hyprx_doctor_note_warn "Pacman database is locked"
    else
        hyprx_doctor_note_ok "Pacman database unlocked"
    fi

    pacnew_count=$(find /etc -xdev -name "*.pacnew" 2>/dev/null | wc -l | tr -d ' ')
    if (( pacnew_count > 0 )); then
        hyprx_doctor_note_warn "$pacnew_count .pacnew file(s) found under /etc - review with pacdiff"
    else
        hyprx_doctor_note_ok "No .pacnew files found"
    fi

    orphan_count=$(pacman -Qdtq 2>/dev/null | grep -c . || true)
    if (( orphan_count > 0 )); then
        hyprx_doctor_note_warn "$orphan_count orphaned package(s) - remove with: pacman -Rns \$(pacman -Qdtq)"
    else
        hyprx_doctor_note_ok "No orphaned packages"
    fi

else
    hyprx_ui_info "pacman not available, skipping Pacman checks"
fi

echo

########################################
# Summary
########################################

hyprx_ui_section "Summary"

if (( DOCTOR_ERRORS > 0 )); then
    hyprx_ui_error "$DOCTOR_ERRORS error(s), $DOCTOR_WARNINGS warning(s) found - see above"
    hyprx_logger_error "Doctor finished: $DOCTOR_ERRORS errors, $DOCTOR_WARNINGS warnings"
    exit 2
elif (( DOCTOR_WARNINGS > 0 )); then
    hyprx_ui_warn "$DOCTOR_WARNINGS warning(s) found, no errors"
    hyprx_logger_warn "Doctor finished: 0 errors, $DOCTOR_WARNINGS warnings"
    exit 1
else
    hyprx_ui_success "All checks passed"
    hyprx_logger_success "Doctor finished clean"
fi

}

########################################
# Run + save a report
########################################

REPORT_DIR="$HOME/.local/state/hyprx/reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/doctor-$(date +%Y%m%d-%H%M%S).log"

run_doctor_checks 2>&1 | tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$REPORT_FILE")
DOCTOR_EXIT="${PIPESTATUS[0]}"

echo
hyprx_ui_info "Full report saved to: $REPORT_FILE"

exit "$DOCTOR_EXIT"
