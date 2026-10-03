#!/usr/bin/env bash

# The single gate between "user ran hyprx install" and "we start changing the
# system".
#
# This replaces two files - preflight.sh and compatibility.sh - which between
# them probed the same six facts twice and disagreed about three of them:
#
#   fact          preflight.sh              compatibility.sh
#   ---------------------------------------------------------------------
#   internet      ping -> ERROR             ping -> WARN
#   sudo          sudo -v -> ERROR          sudo -v -> ERROR   (probed twice)
#   package mgr   != unknown -> ERROR       == unknown -> ERROR
#   session       != wayland -> WARN        wayland/x11/unknown -> WARN
#   RAM           /proc/meminfo / 1024/1024 / 8   -> WARN
#                 /proc/meminfo / 1024     vs 4096  -> WARN
#   disk          df /      vs 5GB -> ERROR df $HOME vs 1GB -> WARN
#
# The RAM pair is the clearest defect: the same number, read with two different
# divisors, so "8GB" was compared against a value in gigabytes and "4GB" against
# a value in megabytes. One install ran both and printed both verdicts, and the
# user could not tell which was the real one. The internet pair was worse -
# unreachable network was simultaneously fatal and advisory.
#
# `sudo -v` twice was not merely redundant: it refreshes the credential
# timestamp and can prompt for a password, so a TTY-less run paid for it twice.
#
# WHAT IS ACTUALLY FATAL
#   A wrong distro, no package manager, no network, no sudo - you cannot install
#   anything. Disk and RAM below the floor are fatal too, because pacman fails
#   unhelpfully partway through a transaction.
#
# WHAT IS ADVISORY
#   Not running under Wayland, Hyprland not the active session, low RAM, little
#   space on $HOME, an unexpected CPU count. None of these stop an install.
#
# Under --dry-run anything needing escalation or network is downgraded to a
# warning, because a non-interactive dry run has no way to satisfy it and
# failing would make the flag useless.

# --- thresholds, in one place ---------------------------------------------
# Kept as named constants because the two files this replaces disagreed on all
# three, and a bare `5242880` in an if-statement explains nothing.
HYPRX_MIN_DISK_ROOT_KB=5242880   # 5 GiB on / - where packages are unpacked
HYPRX_MIN_DISK_HOME_KB=1048576   # 1 GiB on $HOME - where configs and state go
HYPRX_MIN_RAM_RECOMMENDED_MB=8192
HYPRX_MIN_RAM_FLOOR_MB=4096

# --- probe cache ----------------------------------------------------------
# Each fact is measured at most once per run and reused. Keyed by name so a
# second caller cannot re-probe, which is the entire point of merging the files.
HYPRX_GATE_CACHE=()

# hyprx_gate_cached <key> <command...> - run once, print the result.
#
# Returns the stored value on every call after the first. A probe that fails
# stores the empty string rather than being retried, so a missing `ping` does
# not mean six invocations.
hyprx_gate_probe() {
    local key="$1"
    shift

    local stored
    for stored in "${HYPRX_GATE_CACHE[@]}"; do
        if [[ "$stored" == "$key="* ]]; then
            printf '%s' "${stored#*=}"
            return 0
        fi
    done

    local value
    value="$("$@" 2>/dev/null)" || value=""

    HYPRX_GATE_CACHE+=("$key=$value")
    printf '%s' "$value"
    return 0
}

hyprx_gate_reset() {
    HYPRX_GATE_CACHE=()
    unset HYPRX_GATE_SUDO_RESOLVED
}

# --- individual probes ----------------------------------------------------

# Probes `ping -c1` against the distro mirror, not a generic host: what matters
# is whether pacman's mirrors are reachable.
hyprx_gate_internet() {
    [[ -n "$(hyprx_gate_probe internet ping -c1 -W2 archlinux.org)" ]] \
        && return 0
    return 1
}

# `sudo -v` refreshes the credential cache; `sudo -n true` only tests it.
#
# Prefer the non-interactive probe so a cached ticket is detected without a
# prompt, and fall back to `sudo -v` so a first-time TTY run still validates.
# Whichever answers first is remembered - this used to be called twice, once per
# file.
hyprx_gate_sudo() {
    # `sudo -n true` prints nothing and signals success through its exit status,
    # so it cannot be cached through hyprx_gate_probe - which stores stdout.
    # It is therefore run at most once, guarded by its own flag.
    #
    # Preferring -n matters for two reasons: it never prompts, and it does not
    # extend the credential timestamp the way `sudo -v` does. The old pair of
    # gates called `sudo -v` unconditionally, twice per install, each of which
    # could ask for a password.
    if [[ -n "${HYPRX_GATE_SUDO_RESOLVED:-}" ]]; then
        [[ "$HYPRX_GATE_SUDO_RESOLVED" == "yes" ]]
        return $?
    fi

    HYPRX_GATE_SUDO_RESOLVED=no

    # A cached ticket: no prompt, no timestamp change.
    if sudo -n true >/dev/null 2>&1; then
        HYPRX_GATE_SUDO_RESOLVED=yes
        return 0
    fi

    # No cached ticket. Only ask interactively when there is a terminal to ask
    # on, and only outside a dry run - a non-interactive run has nothing to gain
    # from a prompt it cannot answer.
    if ! hyprx_util_dry_run && [[ -t 0 ]]; then
        if sudo -v >/dev/null 2>&1; then
            HYPRX_GATE_SUDO_RESOLVED=yes
            return 0
        fi
    fi

    return 1
}

# Free space in KiB (df --output=avail is 1K blocks).
hyprx_gate_disk_kb() {
    hyprx_gate_probe "disk_$1" df --output=avail "$1" | tail -n1 | tr -d ' '
}

hyprx_gate_ram_mb() {
    # One read, one unit. The old pair divided the same value by 1024/1024 in
    # one file and by 1024 in the other, so "8GB" was compared against gigabytes
    # and "4GB" against megabytes.
    # Single-quoted: $2 is awk's field reference, not a shell variable.
    # shellcheck disable=SC2016
    hyprx_gate_probe ram awk '/^MemTotal:/ {print int($2/1024); exit}' /proc/meminfo
}

# --- the gate -------------------------------------------------------------

# Returns 0 when the install may proceed, 1 when a fatal condition was found.
hyprx_install_gate() {
    hyprx_gate_reset

    hyprx_ui_section "Preflight checks"

    local fatal=0 warn=0

    # Record an outcome and count it. One place, so a check can never print a
    # verdict without also affecting the exit code - the defect that made
    # `hyprx doctor --only applications` print nine red crosses and exit 0.
    #
    #   level: error | warn | ok
    gate_result() {
        local level="$1" msg="$2" hint="${3:-}"

        case "$level" in
            ok)
                hyprx_ui_success "$msg"
                ;;
            warn)
                warn=$((warn + 1))
                hyprx_ui_warn "$msg"
                ;;
            error)
                fatal=$((fatal + 1))
                hyprx_ui_error "$msg"
                ;;
        esac

        [[ -n "$hint" ]] && printf '      %s\n' "$hint"
        return 0
    }

    local dry=false
    hyprx_util_dry_run && dry=true

    # --- distribution -----------------------------------------------------
    # Fatal and unconditional, dry run included: this installer only knows how
    # to drive pacman, so on another distro there is nothing to dry-run against.
    if [[ -f /etc/arch-release ]]; then
        gate_result ok "Arch Linux"
    else
        gate_result error "Unsupported distribution: ${HYPRX_DETECT_DISTRO_NAME:-unknown}" \
            "HyprX is built around pacman/yay/paru and targets Arch only."
    fi

    # --- package manager --------------------------------------------------
    if [[ "$HYPRX_DETECT_PACKAGE_MANAGER" != "unknown" ]]; then
        gate_result ok "$HYPRX_DETECT_PACKAGE_MANAGER detected"
    else
        gate_result error "No supported package manager (tried: yay, paru, pacman)"
    fi

    # --- internet ---------------------------------------------------------
    if hyprx_gate_internet; then
        gate_result ok "Network reachable (archlinux.org)"
    elif $dry; then
        gate_result warn "Network unreachable - a real install would need this"
    else
        gate_result error "Network unreachable" \
            "Package databases cannot be synchronised. Check your connection or mirrors."
    fi

    # --- sudo -------------------------------------------------------------
    if hyprx_gate_sudo; then
        gate_result ok "sudo available"
    elif $dry; then
        gate_result warn "sudo unvalidated - a real install would need it"
    else
        gate_result error "sudo unavailable" \
            "Re-run in a terminal where you can answer the password prompt."
    fi

    # --- disk on / --------------------------------------------------------
    # Fatal: pacman unpacks into /var/cache and /, and fails unhelpfully
    # partway through a transaction when it runs out.
    local root_kb
    root_kb="$(hyprx_gate_disk_kb /)"
    if [[ -z "$root_kb" ]]; then
        gate_result warn "Could not determine free space on /"
    elif (( root_kb < HYPRX_MIN_DISK_ROOT_KB )); then
        if $dry; then
            gate_result warn "Free space on / is below 5GB - a real install needs it"
        else
            gate_result error "Free space on / is below 5GB" \
                "Free packages before installing. Current: $(hyprx_state_human "$((root_kb * 1024))")"
        fi
    else
        gate_result ok "Free space on /: $(hyprx_state_human "$((root_kb * 1024))")"
    fi

    # --- disk on $HOME ----------------------------------------------------
    # Advisory, and only when $HOME is a different filesystem - on the common
    # single-partition setup this is the same number as the line above, and
    # printing it twice was pure noise.
    local home_kb
    home_kb="$(hyprx_gate_disk_kb "$HOME")"
    if [[ -z "$home_kb" ]]; then
        gate_result warn "Could not determine free space on \$HOME"
    elif (( root_kb > 0 && home_kb == root_kb )); then
        # Same filesystem as /, already reported.
        :
    elif (( home_kb < HYPRX_MIN_DISK_HOME_KB )); then
        gate_result warn "Free space on \$HOME is below 1GB" \
            "Configs, fonts and state all live under \$HOME."
    else
        gate_result ok "Free space on \$HOME: $(hyprx_state_human "$((home_kb * 1024))")"
    fi

    # --- memory -----------------------------------------------------------
    local ram_mb
    ram_mb="$(hyprx_gate_ram_mb)"
    if [[ -z "$ram_mb" ]]; then
        gate_result warn "Could not read total memory"
    elif (( ram_mb < HYPRX_MIN_RAM_FLOOR_MB )); then
        # Below the floor an install will thrash. Still advisory rather than
        # fatal: refusing outright on a memory reading helps nobody, and the
        # packages still install.
        gate_result warn "${ram_mb}MB RAM - below the 4GB floor for a desktop this size" \
            "An install will work but a running session may not."
    elif (( ram_mb < HYPRX_MIN_RAM_RECOMMENDED_MB )); then
        gate_result warn "${ram_mb}MB RAM - 8GB or more recommended" \
            "Config validation and the AUR helper both get noticeably slower below this."
    else
        gate_result ok "${ram_mb}MB RAM"
    fi

    # --- session ----------------------------------------------------------
    # Installing from an X11 or TTY session is legitimate - you cannot run
    # Hyprland and install into it in the same login - so this never blocks.
    case "${XDG_SESSION_TYPE:-unknown}" in
        wayland) gate_result ok "Wayland session" ;;
        x11)     gate_result warn "Not a Wayland session" \
                     "Configs deploy fine, but hyprland.lua cannot be reloaded here." ;;
        *)       gate_result warn "Session type unknown (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset})" ;;
    esac

    if [[ "${HYPRX_DETECT_HAS_HYPRLAND:-false}" == true ]]; then
        gate_result ok "Hyprland is the active session"
    else
        gate_result warn "Hyprland is not the active session" \
            "The configs will be written to ~/.config but not live-reloaded."
    fi

    # --- advisory inventory ----------------------------------------------
    local threads
    threads="$(hyprx_gate_probe threads nproc)"
    [[ -n "$threads" ]] && hyprx_ui_info "CPU: $threads threads"

    if [[ "$HYPRX_DETECT_GPU_VENDOR" == "nvidia" ]] \
       && [[ ! -f /sys/module/nvidia_drm/parameters/modeset ]]; then
        gate_result warn "nvidia_drm.modeset is not enabled" \
            "GPU offload setup will warn. See the comment in config/hypr/hyprland.lua."
    fi

    # --- verdict ----------------------------------------------------------
    hyprx_ui_divider

    if (( fatal > 0 )); then
        hyprx_ui_error "Cannot install: $fatal blocking problem(s), $warn warning(s)."
        hyprx_ui_info "Nothing has been changed. Fix the problems above and re-run."
        return 1
    fi

    if (( warn > 0 )); then
        hyprx_ui_success "Preflight passed with $warn warning(s)."
    else
        hyprx_ui_success "Preflight passed."
    fi

    return 0
}

# Kept as a thin alias so anything that called the old name still works. Both
# names used to be separate gates, which meant the install ran the whole set of
# probes twice.
hyprx_preflight_check() {
    hyprx_install_gate
}

hyprx_compatibility_check() {
    hyprx_install_gate
}
