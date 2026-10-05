#!/usr/bin/env bash

# systemd service handling, driven by services.list.
#
# This file existed as a claim and not as code. services.list was read only by
# doctor.sh, so doctor reported every HyprX-managed service as "installed but
# not enabled" forever, and both README.md:15 and commands/install.sh:20
# promised an enable stage that had never existed.
#
# SCOPE
# -----
# services.list mixes system and user units and gives no indication which is
# which:
#
#   bluetooth       system    bluez
#   docker          system    docker
#   firewalld       system    firewalld
#   NetworkManager  system    networkmanager
#   pipewire        user      pipewire   (user unit on Arch)
#   supergfxd       system    supergfxctl
#   asusd           system    asusctl
#
# Guessing wrong is not an option: `systemctl --user enable NetworkManager`
# fails, and `systemctl enable` on a user unit fails the same way. So the scope
# is probed rather than assumed - the unit is looked up in the system manager
# first and the user manager second, and whichever answers is used.
#
# A service in neither scope is reported as "no unit file", which almost always
# means the providing package was not installed. That is a real and actionable
# message, and doctor repeats it.

# Launched from the compositor's exec-once chain instead of being enabled.
# Enabling it would race that launch and systemd would burn five retries on the
# loser - the same reason lib/installer/deploy.sh disables swaync.service.
HYPRX_SERVICE_NO_ENABLE="swaync.service"

HYPRX_SERVICES_ENABLED=()
HYPRX_SERVICES_FAILED=()
HYPRX_SERVICES_SKIPPED=()

# Strip comments and surrounding whitespace from one line.
hyprx_services_clean() {
    local svc="${1%%#*}"
    svc="${svc#"${svc%%[![:space:]]*}"}"
    svc="${svc%"${svc##*[![:space:]]}"}"
    printf '%s' "$svc"
}

# services.list entries are bare names (`bluetooth`, `NetworkManager`), but
# `systemctl list-unit-files` matches on the FULL unit name - a bare
# `NetworkManager` matches nothing and exits 1. Every entry in the file is
# bare, so all seven answered "no unit file in either scope": networkmanager,
# pipewire, firewalld and bluez were installed on the test machine and each was
# reported as absent, and the stage enabled nothing (Enabled 0, Skipped 7) on a
# system that had four of them.
#
# doctor.sh already appends the suffix (commands/doctor.sh:652), which is why
# doctor and install disagreed about the same machine. Idempotent: an entry that
# already names a type (`foo.timer`, `greetd.socket`) is left alone.
hyprx_service_unit_name() {
    local svc="$1"
    if [[ "$svc" == *.* ]]; then
        printf '%s' "$svc"
    else
        printf '%s.service' "$svc"
    fi
}

hyprx_services_read() {
    local file="$HYPRX_ROOT/services.list"
    HYPRX_SERVICES=()

    [[ -f "$file" ]] || return 0

    local line svc
    while IFS= read -r line || [[ -n "$line" ]]; do
        svc="$(hyprx_services_clean "$line")"
        [[ -z "$svc" ]] && continue
        HYPRX_SERVICES+=("$svc")
    done <"$file"

    return 0
}

# Which manager owns this unit: "system", "user", or empty for neither.
# Both probes are non-fatal; a missing bus simply answers nothing.
hyprx_service_scope() {
    local unit
    unit="$(hyprx_service_unit_name "$1")"

    if systemctl list-unit-files "$unit" --no-legend >/dev/null 2>&1 \
       && systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
        printf 'system'
        return 0
    fi

    if systemctl --user list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
        printf 'user'
        return 0
    fi

    printf ''
    return 1
}

hyprx_service_is_enabled() {
    local scope="$1" unit="$2" state

    if [[ "$scope" == "user" ]]; then
        state="$(systemctl --user is-enabled "$unit" 2>/dev/null)" || state=""
    else
        state="$(sudo systemctl is-enabled "$unit" 2>/dev/null)" || state=""
    fi

    case "$state" in
        enabled|enabled-runtime|static|linked|alias|indirect) return 0 ;;
        *) return 1 ;;
    esac
}

hyprx_service_enable() {
    local scope="$1" unit="$2"

    if [[ "$scope" == "user" ]]; then
        systemctl --user enable --now "$unit" >/dev/null 2>&1
    else
        sudo systemctl enable --now "$unit" >/dev/null 2>&1
    fi
}

hyprx_service_disable() {
    local scope="$1" unit="$2"

    if [[ "$scope" == "user" ]]; then
        systemctl --user disable "$unit" >/dev/null 2>&1
    else
        sudo systemctl disable "$unit" >/dev/null 2>&1
    fi
}

hyprx_services_enable() {
    hyprx_ui_section "Systemd services"

    HYPRX_SERVICES_ENABLED=()
    HYPRX_SERVICES_FAILED=()
    HYPRX_SERVICES_SKIPPED=()

    local file="$HYPRX_ROOT/services.list"

    if [[ ! -f "$file" ]]; then
        hyprx_ui_info "No services.list - skipping"
        return 0
    fi

    hyprx_services_read

    if (( ${#HYPRX_SERVICES[@]} == 0 )); then
        hyprx_ui_info "services.list is empty - nothing to enable"
        return 0
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        hyprx_ui_info "systemctl not available - skipping service setup"
        return 0
    fi

    local dry=false
    hyprx_util_dry_run && dry=true

    # A system-scope enable needs sudo. Ask once up front so the first unit
    # does not silently eat the whole run's timeouts on a hidden prompt, and so
    # the dry-run case can skip the question entirely.
    local can_sudo=false
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        can_sudo=true
    fi

    local svc unit scope
    for svc in "${HYPRX_SERVICES[@]}"; do
        unit="$(hyprx_service_unit_name "$svc")"

        # --- deliberately not enabled -------------------------------------
        if [[ " $HYPRX_SERVICE_NO_ENABLE " == *" $unit "* ]]; then
            HYPRX_SERVICES_SKIPPED+=("$svc")
            hyprx_ui_info "$svc: left disabled (HyprX launches it from the compositor)"
            hyprx_event service.skipped name="$svc" reason="compositor-launched"
            continue
        fi

        # --- which manager owns it ----------------------------------------
        scope="$(hyprx_service_scope "$unit")" || scope=""

        if [[ -z "$scope" ]]; then
            HYPRX_SERVICES_SKIPPED+=("$svc")
            hyprx_ui_warn "$svc: no unit file in either scope. Its package is probably not installed."
            hyprx_event service.skipped name="$svc" reason="no-unit-file"
            continue
        fi

        # --- already in the wanted state ----------------------------------
        if hyprx_service_is_enabled "$scope" "$unit"; then
            HYPRX_SERVICES_ENABLED+=("$svc")
            hyprx_ui_info "$svc: already enabled ($scope)"
            hyprx_event service.skipped name="$svc" reason="already-enabled"
            continue
        fi

        if $dry; then
            hyprx_util_would "systemctl $scope enable --now $unit"
            HYPRX_SERVICES_ENABLED+=("$svc")
            hyprx_event service.enabled name="$svc" scope="$scope"
            continue
        fi

        # --- enable it ---------------------------------------------------
        if [[ "$scope" == "system" ]] && ! $can_sudo; then
            HYPRX_SERVICES_FAILED+=("$svc")
            hyprx_ui_warn "$svc: needs sudo and no cached ticket is available - skipped"
            hyprx_event service.failed name="$svc" reason="no-sudo-ticket"
            continue
        fi

        if hyprx_service_enable "$scope" "$unit"; then
            HYPRX_SERVICES_ENABLED+=("$svc")
            hyprx_ui_success "$svc: enabled ($scope)"
            hyprx_event service.enabled name="$svc" scope="$scope"
        else
            HYPRX_SERVICES_FAILED+=("$svc")
            hyprx_ui_error "$svc: systemctl enable --now failed ($scope)"
            hyprx_event service.failed name="$svc" reason="systemctl-failed"
        fi
    done

    echo
    printf "%-20s %d\n" "Enabled" "${#HYPRX_SERVICES_ENABLED[@]}"
    printf "%-20s %d\n" "Skipped" "${#HYPRX_SERVICES_SKIPPED[@]}"
    printf "%-20s %d\n" "Failed"  "${#HYPRX_SERVICES_FAILED[@]}"
    echo

    if (( ${#HYPRX_SERVICES_FAILED[@]} > 0 )); then
        hyprx_ui_warn "Some services could not be enabled."
        hyprx_ui_info "Check with: systemctl --failed"
        return 1
    fi

    return 0
}

# Re-enable only the ones that drifted. Separate from install because a user
# who disabled a service on purpose should not have it turned back on by a
# routine `hyprx update`.
hyprx_services_verify() {
    local svc unit scope drift=0

    hyprx_services_read
    (( ${#HYPRX_SERVICES[@]} == 0 )) && return 0

    for svc in "${HYPRX_SERVICES[@]}"; do
        unit="$(hyprx_service_unit_name "$svc")"
        [[ " $HYPRX_SERVICE_NO_ENABLE " == *" $unit "* ]] && continue

        scope="$(hyprx_service_scope "$unit")" || scope=""

        if [[ -z "$scope" ]]; then
            hyprx_ui_warn "$svc: no unit file (package not installed?)"
            drift=$((drift + 1))
            continue
        fi

        if ! hyprx_service_is_enabled "$scope" "$unit"; then
            hyprx_ui_warn "$svc: installed but not enabled ($scope)"
            drift=$((drift + 1))
        fi
    done

    return "$drift"
}
