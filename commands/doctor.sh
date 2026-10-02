#!/usr/bin/env bash

# Tallies feed the summary and the exit code. Only real health signals are
# tallied; the Applications section is a presence report and uses plain printers.
#
# Every tally is also recorded for --json, so the two output modes cannot drift
# apart: both read the same three note functions.
DOCTOR_WARNINGS=0
DOCTOR_ERRORS=0
DOCTOR_SUGGESTIONS=()
DOCTOR_JSON_FINDINGS=()
DOCTOR_JSON=false

doctor_json_add() {
    DOCTOR_JSON_FINDINGS+=("$1"$'\t'"$2")
}

hyprx_doctor_note_ok() {
    doctor_json_add ok "$1"
    hyprx_ui_success "$1"
}

hyprx_doctor_note_warn() {
    doctor_json_add warn "$1"
    hyprx_ui_warn "$1"
    DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
}

hyprx_doctor_note_err() {
    doctor_json_add error "$1"
    hyprx_ui_error "$1"
    DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
}

hyprx_doctor_suggest() {
    local s
    for s in "${DOCTOR_SUGGESTIONS[@]}"; do
        [[ "$s" == "$1" ]] && return 0
    done
    DOCTOR_SUGGESTIONS+=("$1")
}

# 0 clean, 1 warnings, 2 errors. Shared by the human report and --json so the
# two modes always agree on the exit status.
doctor_exit_code() {
    if (( DOCTOR_ERRORS > 0 )); then
        hyprx_ui_error "$DOCTOR_ERRORS error(s), $DOCTOR_WARNINGS warning(s) found - see above"
        hyprx_logger_error "Doctor finished: $DOCTOR_ERRORS errors, $DOCTOR_WARNINGS warnings"
        exit 2
    elif (( DOCTOR_WARNINGS > 0 )); then
        hyprx_ui_warn "$DOCTOR_WARNINGS warning(s) found, no errors"
        hyprx_logger_warn "Doctor finished: 0 errors, $DOCTOR_WARNINGS warnings"
        exit 1
    fi
    hyprx_ui_success "All checks passed"
    hyprx_logger_success "Doctor finished clean"
    exit 0
}

doctor_json_escape() {
    local s="${1//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/ }"
    s="${s//$'\n'/ }"
    printf '%s' "$s"
}

doctor_json_emit() {
    local uptime
    uptime="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"

    printf '{\n'
    printf '  "host": "%s",\n'   "$(doctor_json_escape "$(uname -n)")"
    printf '  "distro": "%s",\n' "$(doctor_json_escape "$HYPRX_DETECT_DISTRO_NAME")"
    printf '  "kernel": "%s",\n' "$(doctor_json_escape "$(uname -r)")"
    printf '  "session": "%s",\n' "$(doctor_json_escape "${XDG_SESSION_TYPE:-unknown}")"
    printf '  "uptime_seconds": %s,\n' "${uptime:-0}"
    printf '  "summary": { "errors": %d, "warnings": %d },\n' "$DOCTOR_ERRORS" "$DOCTOR_WARNINGS"

    printf '  "suggestions": ['
    local i
    for i in "${!DOCTOR_SUGGESTIONS[@]}"; do
        [[ "$i" -gt 0 ]] && printf ','
        printf '\n    "%s"' "$(doctor_json_escape "${DOCTOR_SUGGESTIONS[$i]}")"
    done
    (( ${#DOCTOR_SUGGESTIONS[@]} )) && printf '\n  ' || printf ']'
    printf '],\n'

    printf '  "findings": ['
    local last=$((${#DOCTOR_JSON_FINDINGS[@]} - 1))
    for i in "${!DOCTOR_JSON_FINDINGS[@]}"; do
        local status detail
        IFS=$'\t' read -r status detail <<<"${DOCTOR_JSON_FINDINGS[$i]}"
        printf '\n    { "status": "%s", "detail": "%s" }' \
            "$status" "$(doctor_json_escape "$detail")"
        [[ "$i" -lt "$last" ]] && printf ','
    done
    (( ${#DOCTOR_JSON_FINDINGS[@]} )) && printf '\n  ' || printf ']'
    printf ']\n'
    printf '}\n'
}

# Returns 0 valid, 1 invalid, 2 no such validator.
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

# Units HyprX installs but deliberately never enables. swaync is launched from
# the compositor's exec-once chain instead, so its unit is always "failed" and
# flagging it every run is noise that trains you to ignore this section.
DOCTOR_EXPECTED_FAILED_UNITS="swaync.service"

check_failed_units() {
    local scope="$1"
    local label="$2"
    local output remaining
    local -a systemctl_args=()

    [[ -n "$scope" ]] && systemctl_args+=("$scope")

    if ! output=$(systemctl "${systemctl_args[@]}" --failed --no-legend 2>&1); then
        hyprx_ui_info "$label: unable to query (systemctl unavailable or bus unreachable)"
        return
    fi

    # Drop the expected units, keeping every other row intact. The unit name is
    # not always the first field - systemctl prefixes rows with a status glyph -
    # so match against every field.
    remaining="$(
        printf '%s\n' "$output" | awk -v skip="$DOCTOR_EXPECTED_FAILED_UNITS" '
            BEGIN { n = split(skip, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") drop[a[i]] = 1 }
            { hit = 0
              for (i = 1; i <= NF; i++) if ($i in drop) { hit = 1; break }
              if (!hit && NF) print }'
    )"

    if [[ -n "$(printf '%s' "$remaining" | tr -d '[:space:]')" ]]; then
        hyprx_doctor_note_warn "$label: failed units detected"
        printf '%s\n' "$remaining"
    else
        hyprx_doctor_note_ok "$label: no failed units"
        printf '%s\n' "$output" | awk -v skip="$DOCTOR_EXPECTED_FAILED_UNITS" '
            BEGIN { n = split(skip, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") drop[a[i]] = 1 }
            { hit = 0
              for (i = 1; i <= NF; i++) if ($i in drop) { hit = 1; name = $i; break }
              if (hit) printf "  %s: expected - launched from the compositor, not enabled\n", name }'
    fi
}

# Called from the session section and from the gpu section.
gpu_checks() {
    if systemctl is-active --quiet supergfxd 2>/dev/null; then
        hyprx_doctor_note_ok "supergfxd active"
    else
        hyprx_doctor_note_err "supergfxd installed but not running - dGPU cannot power-manage or PRIME offload correctly"
    fi

    hyprx_ui_info "Graphics mode: $(supergfxctl -g 2>/dev/null || echo unknown)"

    local modeset_file modeset_val
    modeset_file="/sys/module/nvidia_drm/parameters/modeset"
    if [[ -f "$modeset_file" ]]; then
        modeset_val="$(cat "$modeset_file" 2>/dev/null || echo "?")"
        if [[ "$modeset_val" == "Y" ]]; then
            hyprx_doctor_note_ok "nvidia_drm.modeset enabled"
        else
            hyprx_doctor_note_warn "nvidia_drm.modeset is not enabled (currently: $modeset_val) - PRIME render offload will not work"
        fi
    else
        hyprx_ui_info "nvidia_drm module not loaded"
    fi

    local nvidia_pci runtime_status_file
    nvidia_pci="$(lspci -d 10de: -D 2>/dev/null | awk '{print $1; exit}' || true)"
    if [[ -n "$nvidia_pci" && -f "/sys/bus/pci/devices/$nvidia_pci/power/runtime_status" ]]; then
        runtime_status_file="/sys/bus/pci/devices/$nvidia_pci/power/runtime_status"
        hyprx_ui_info "dGPU runtime PM status: $(cat "$runtime_status_file" 2>/dev/null || echo unknown)"
    fi
}

run_doctor_checks() {
    hyprx_ui_header
    hyprx_logger_info "Running doctor"
    echo

    if doctor_wants configuration; then
    # Configuration
    hyprx_ui_section "Configuration"
    hyprx_table_header
    hyprx_table_row "Theme"          "${HYPRX_CONFIG_THEME:-Default}"
    hyprx_table_row "Terminal"       "${TERMINAL:-Unknown}"
    hyprx_table_row "Browser"        "${BROWSER:-Unknown}"
    hyprx_table_row "Editor"         "${EDITOR:-Unknown}"
    hyprx_table_row "File Manager"   "${FILE_MANAGER:-Unknown}"
    hyprx_table_row "Launcher"       "${LAUNCHER:-Unknown}"
    echo

    fi

    if doctor_wants applications; then
    # Applications
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

    fi

    if doctor_wants system; then
    # System Information
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

    fi

    if doctor_wants validation; then
    # Config Validation
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

    fi

    if doctor_wants drift; then
    # Config Deployment Drift
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

    fi

    if doctor_wants storage; then
    # Storage
    hyprx_ui_section "Storage"
    root_usage="$(df -h / | awk 'NR==2 {print $5}')"
    hyprx_table_header
    hyprx_table_row "Root Usage" "$root_usage"
    echo

    fi

    if doctor_wants memory; then
    # Memory
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

    fi

    if doctor_wants swap; then
    # Swap
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

    fi

    if doctor_wants systemd; then
    # Systemd - System & User Services
    hyprx_ui_section "Systemd"
    check_failed_units "" "System services"
    check_failed_units "--user" "User services"
    echo

    fi

    if doctor_wants services; then
    # HyprX Managed Services
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

    fi

    if doctor_wants session; then
    # Session Health
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

    fi

    if doctor_wants gpu; then
        hyprx_ui_section "Hybrid GPU"
        if hyprx_util_command_exists supergfxctl; then
            gpu_checks
        else
            # Always say why there is nothing to report. A selectable section
            # that silently vanishes reads as a passing check.
            hyprx_ui_info "supergfxctl not installed - no hybrid GPU to inspect"
        fi
        echo
    fi

    if doctor_wants network; then
    # Network & Radios
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

    fi

    if doctor_wants pacman; then
    # Pacman
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

    fi

    # Session daemons
    # Everything hyprland.lua autostarts. Doctor previously verified only
    # waybar and hyprpaper - the other four failed silently at some point
    # during development, which is the whole class of bug worth catching.
    if doctor_wants daemons; then
        hyprx_ui_section "Session Daemons"

        if ! command -v pgrep >/dev/null 2>&1; then
            # procps is not installed everywhere. Reporting every daemon as down
            # would be a lie, so say the probe could not run instead.
            hyprx_ui_info "pgrep not available - cannot inspect running processes (install procps)"
            hyprx_doctor_suggest "pacman -S procps"
        else

        # label | process pattern | fix hint
        # Only waybar is a layer-shell surface, so only waybar gets a surface
        # check - the others are ordinary processes with no surface to verify.
        while IFS='|' read -r label pattern hint; do
            [[ -z "$label" ]] && continue
            if pgrep -f "$pattern" >/dev/null 2>&1; then
                hyprx_doctor_note_ok "$label: running"
            else
                hyprx_doctor_note_warn "$label: not running"
                [[ -n "$hint" ]] && hyprx_doctor_suggest "$hint"
            fi
        done <<'EOF'
waybar|waybar|hyprctl hypr exec '~/.config/waybar/scripts/ensure-waybar.sh --restart'
swaync|swaync|
hypridle|hypridle|
nm-aplet|nm-aplet --indicator|
wallust theming|wallust-hyprpaper-sync|
music daemon|music-daemon.sh|
bluetooth daemon|bluetooth-daemon.sh|
EOF

        # A waybar that is running as a process but has no registered layer is
        # the exact failure that cost a session earlier, so check it directly.
        if pgrep -x waybar >/dev/null 2>&1; then
            if hyprctl layers 2>/dev/null | grep -q "namespace: waybar"; then
                hyprx_doctor_note_ok "waybar: registered layer present"
            else
                hyprx_doctor_note_err "waybar is running but has no registered layer"
                hyprx_doctor_suggest "hyprctl hypr exec '~/.config/waybar/scripts/ensure-waybar.sh --restart'"
            fi
        fi

        # hyprpaper is checked in Session Health (it also verifies the surface).
        if pgrep -x hyprpaper >/dev/null 2>&1; then
            hyprx_doctor_note_ok "hyprpaper: running"
        else
            hyprx_doctor_note_warn "hyprpaper: not running"
            hyprx_doctor_suggest "${HOME}/.local/share/hyprx/scripts/wallpaper-restore.sh"
        fi

        fi

        echo
    fi

    # Battery and thermals
    # Nothing here existed before. This is a hybrid-GPU laptop where battery
    # health and thermals are the numbers that actually matter.
    if doctor_wants battery; then
        hyprx_ui_section "Battery & Thermals"

        local bat
        bat="$(ls /sys/class/power_supply 2>/dev/null | grep '^BAT' | head -n1)"

        if [[ -n "$bat" ]]; then
            local cap status health charge_now charge_full
            cap="$(cat "/sys/class/power_supply/$bat/capacity" 2>/dev/null || echo "?")"
            status="$(cat "/sys/class/power_supply/$bat/status" 2>/dev/null || echo "?")"

            if [[ "$cap" =~ ^[0-9]+$ ]]; then
                if (( cap <= 15 )) && [[ "$status" != "Charging" ]]; then
                    hyprx_doctor_note_warn "Battery at $cap% and not charging"
                else
                    hyprx_doctor_note_ok "Battery $cap% ($status)"
                fi
            else
                hyprx_doctor_note_ok "Battery present ($status)"
            fi

            charge_now="$(cat "/sys/class/power_supply/$bat/charge_now" 2>/dev/null || echo 0)"
            charge_full="$(cat "/sys/class/power_supply/$bat/charge_full" 2>/dev/null || echo 0)"

            if [[ "$charge_now" =~ ^[0-9]+$ ]] && [[ "$charge_full" =~ ^[0-9]+$ ]] && (( charge_full > 0 )); then
                health=$(( charge_now * 100 / charge_full ))
                if (( health < 60 )); then
                    hyprx_doctor_note_warn "Battery health about $health% of design capacity"
                else
                    hyprx_doctor_note_ok "Battery health about $health% of design capacity"
                fi
            fi
        else
            hyprx_ui_info "No battery detected"
        fi

        # Thermals. sensors -u prints the chip name at column 0, an optional
        # sub-heading ("Package id 0:") indented under it, then the readings.
        # Reporting bare temp1_input/temp2_input values is unreadable when a
        # machine has three chips, so each reading is labelled with the chip and
        # sub-heading it came from and the hottest ones are surfaced first.
        if command -v sensors >/dev/null 2>&1; then
            local temps
            temps="$(sensors -u 2>/dev/null | awk '
                # A chip header is a bare token at column 0: coretemp-isa-0000,
                # mt7921_phy0-pci-2d00. Nothing else looks like this.
                /^[A-Za-z0-9][A-Za-z0-9_.-]*$/  { chip = $0; label = ""; next }
                # A feature heading also sits at column 0 and ends in a colon:
                # "Package id 0:", "Core 0:", "temp1:". "Adapter: PCI adapter"
                # does not qualify because it has content after the colon.
                /^[^[:space:]].*:$/            { t = $0
                                                sub(/:$/, "", t)
                                                label = t; next }
                # Readings are the only indented lines that carry a value.
                /^[[:space:]]+temp[0-9]+_input:/ {
                                                v = $2
                                                if (v ~ /^[0-9.]+$/) {
                                                    t = $1; sub(/:$/, "", t)
                                                    # A label already identifies the
                                                    # reading, so the tempN_input
                                                    # suffix would just be noise.
                                                    printf "%s %s|%.1f\n", \
                                                        chip, (label ? label : t), v
                                                } }')"

            if [[ -n "$temps" ]]; then
                printf '%s\n' "$temps" | sort -t'|' -k2 -gr | head -6 | while IFS='|' read -r where v; do
                    printf "  %-38s %5.1f C\n" "$where" "$v"
                done

                local n hottest
                n="$(printf '%s\n' "$temps" | grep -c . || true)"
                hottest="$(printf '%s\n' "$temps" | sort -t'|' -k2 -gr | head -1 | cut -d'|' -f2)"

                if (( n > 6 )); then
                    echo "  (the 6 hottest of $n sensors)"
                fi
                if awk -v h="${hottest:-0}" 'BEGIN { exit !(h >= 85) }'; then
                    hyprx_doctor_note_warn "Hottest sensor is ${hottest} C - thermal throttling likely"
                fi
            else
                hyprx_ui_info "lm-sensors returned no temperatures"
            fi
        else
            hyprx_ui_info "lm-sensors not installed - skipping temperatures (pacman -S lm_sensors)"
        fi

        echo
    fi

    # Disk usage where it actually accumulates
    # Root usage alone hid 7G in ~/.cache and 4G in the pacman cache.
    if doctor_wants diskusage; then
        hyprx_ui_section "Disk Usage"

        hyprx_table_header
        hyprx_table_row "Root" "$(df -h / | awk 'NR==2 {print $5 " used of " $2}')"
        hyprx_table_row "Home" "$(df -h "$HOME" | awk 'NR==2 {print $5 " used of " $2}')"

        echo

        local d sz
        for d in "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/state" /var/cache/pacman/pkg; do
            [[ -d "$d" ]] || continue
            sz="$(hyprx_state_size "$d")"
            hyprx_table_row "${d/#$HOME/\~}" "$(hyprx_state_human "${sz:-0}")"
        done

        # Only nag when it is actually worth acting on.
        local cache_sz
        cache_sz="$(hyprx_state_size "$HOME/.cache")"
        if [[ -n "$cache_sz" ]] && (( cache_sz > 1073741824 )); then
            hyprx_doctor_note_warn "${HOME}/.cache is $(hyprx_state_human "$cache_sz")"
            hyprx_doctor_suggest "hyprx clean --deep --dry-run    # then without --dry-run to reclaim it"
        fi

        echo
    fi

    # --json emits from the collected findings, so the human summary and its
    # exit are skipped; the caller turns the tallies into the exit code.
    $DOCTOR_JSON && return 0

    hyprx_ui_section "Summary"
    if (( ${#DOCTOR_SUGGESTIONS[@]} > 0 )); then
        echo
        echo "Suggested next steps:"
        local s
        for s in "${DOCTOR_SUGGESTIONS[@]}"; do
            echo "  $s"
        done
        echo
    fi
    doctor_exit_code
}


########################################
# Arguments
########################################

DOCTOR_ONLY=""
DOCTOR_SKIP=""
DOCTOR_NO_REPORT=false

doctor_usage() {
    cat <<'EOF'
Usage:
    hyprx doctor [options]

Options:
    --only <list>    Run only these sections (comma separated).
    --skip <list>    Skip these sections (comma separated).
    --json           Emit machine-readable JSON instead of the report.
    --no-report      Do not write a timestamped report file.
    -h, --help       Show this help.

Sections:
    configuration  applications  system  validation  drift  storage
    memory  swap  systemd  services  session  gpu  network  pacman
    daemons  battery  diskusage

An unknown section name is rejected rather than silently running nothing.
EOF
}

DOCTOR_SECTIONS="configuration applications system validation drift storage memory swap systemd services session gpu network pacman daemons battery diskusage"

# A section runs when it is neither excluded by --skip nor absent from --only.
doctor_wants() {
    local name="$1"
    if [[ -n "$DOCTOR_ONLY" ]]; then
        [[ ",$DOCTOR_ONLY," == *",$name,"* ]] || return 1
    fi
    [[ ",$DOCTOR_SKIP," == *",$name,"* ]] && return 1
    return 0
}

# A mistyped name would otherwise run nothing and look like a clean bill of
# health, so reject it and print the valid names.
doctor_validate_sections() {
    local flag="$1" list="$2" name
    local -a names
    IFS=',' read -r -a names <<<"$list"

    for name in "${names[@]}"; do
        [[ -z "$name" ]] && continue
        if [[ " $DOCTOR_SECTIONS " != *" $name "* ]]; then
            hyprx_ui_error "Unknown section for $flag: $name"
            hyprx_ui_info "Valid sections: $DOCTOR_SECTIONS"
            return 1
        fi
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)  DOCTOR_ONLY="${2:-}"; shift 2 ;;
        --skip)  DOCTOR_SKIP="${2:-}"; shift 2 ;;
        --json)  DOCTOR_JSON=true; shift ;;
        --no-report) DOCTOR_NO_REPORT=true; shift ;;
        -h|--help) doctor_usage; exit 0 ;;
        *) hyprx_ui_error "Unknown option: $1"; doctor_usage; exit 1 ;;
    esac
done

[[ -n "$DOCTOR_ONLY" ]] && { doctor_validate_sections --only  "$DOCTOR_ONLY"  || exit 1; }
[[ -n "$DOCTOR_SKIP" ]] && { doctor_validate_sections --skip  "$DOCTOR_SKIP"  || exit 1; }

# --json and --only together would emit a partial document that looks complete.
if $DOCTOR_JSON && [[ -n "$DOCTOR_ONLY" ]]; then
    hyprx_ui_error "--json cannot be combined with --only (a partial document would look complete)"
    exit 1
fi

########################################
# Run + save a report
########################################

# stdout of the checks is discarded so the document is the only thing on it;
# the tallies and findings survive because they live in variables.
if $DOCTOR_JSON; then
    run_doctor_checks >/dev/null
    doctor_json_emit
    if (( DOCTOR_ERRORS > 0 )); then exit 2; fi
    (( DOCTOR_WARNINGS > 0 )) && exit 1
    exit 0
fi

REPORT_DIR="$HYPRX_STATE_REPORT_DIR"

if $DOCTOR_NO_REPORT; then
    run_doctor_checks
    exit $?
fi

mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/doctor-$(date +%Y%m%d-%H%M%S).log"

run_doctor_checks 2>&1 | tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$REPORT_FILE")
DOCTOR_EXIT="${PIPESTATUS[0]}"

echo
hyprx_ui_info "Full report saved to: $REPORT_FILE"

exit "$DOCTOR_EXIT"
