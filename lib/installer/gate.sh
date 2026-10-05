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

# hyprx_gate_probe <key> <varname> <command...> - run once, store the result in
# <varname>.
#
# The value is returned through a NAMED VARIABLE, not through stdout. Every call
# site originally captured stdout with `$(...)`, and a command substitution runs
# in a subshell: the `HYPRX_GATE_CACHE+=(...)` append happened inside that
# subshell and evaporated when it exited. So the cache looked right, was read as
# correct by the review, and in fact never held a single entry - the second
# caller always re-probed, which is the one thing a cache exists to prevent.
# Returning through a variable keeps the write in the caller's shell.
#
# Because bash uses dynamic scoping, `printf -v` lands in the caller's local if
# the caller declared one - so declare the destination local before calling.
# Every local here is prefixed `__hyprx_`, so a destination can never collide
# with one of them and be captured by the wrong scope.
#
# One more trap: the caller must invoke this function DIRECTLY, not inside
# `$(...)`. A command substitution is a subshell, and the cache append below
# would happen there and evaporate with it - which is exactly how this cache
# managed to never hold a single entry while looking correct.
#
# Returns the stored value on every call after the first. A probe that fails
# stores the empty string rather than being retried, so a missing probe tool does
# not turn into six invocations.
hyprx_gate_probe() {
    local __hyprx_key="$1"
    local __hyprx_dest="$2"
    shift 2

    local __hyprx_stored
    for __hyprx_stored in "${HYPRX_GATE_CACHE[@]}"; do
        if [[ "$__hyprx_stored" == "$__hyprx_key="* ]]; then
            printf -v "$__hyprx_dest" '%s' "${__hyprx_stored#*=}"
            return 0
        fi
    done

    local __hyprx_value
    __hyprx_value="$("$@" 2>/dev/null)" || __hyprx_value=""

    HYPRX_GATE_CACHE+=("$__hyprx_key=$__hyprx_value")
    printf -v "$__hyprx_dest" '%s' "$__hyprx_value"
    return 0
}

hyprx_gate_reset() {
    HYPRX_GATE_CACHE=()
    unset HYPRX_GATE_SUDO_RESOLVED
}

# --- individual probes ----------------------------------------------------

# Reachability, in order of preference.
#
# `ping` was the original probe and it is the wrong one: ping lives in `iputils`,
# which is not a dependency of anything here, so on a minimal system - notably
# the archlinux:base container the test suite runs in - the probe itself is
# missing. The gate read that as "network unreachable" and aborted the install,
# which is the one conclusion a missing tool must never produce.
#
# So the ladder is: bash's own /dev/tcp (no binary at all, and bash is already
# running this function), then curl, then wget, then ping. Only if NONE of them
# is available is the answer unknown rather than false.
#
# hyprx_gate_internet_state <varname> - stores ok | down | unknown.
#
# Takes a destination instead of printing, for the same reason hyprx_gate_probe
# does: this is called from inside `case "$(...)"`, and a command substitution
# runs the whole call in a subshell - the cache append would evaporate with it.
hyprx_gate_internet_state() {
    local __hyprx_dest="$1"
    hyprx_gate_probe internet "$__hyprx_dest" hyprx_gate_internet_probe
    # A failed probe stores the empty string; an empty answer means nobody could
    # tell, which is not the same as down.
    if [[ -z "${!__hyprx_dest:-}" ]]; then
        printf -v "$__hyprx_dest" '%s' "unknown"
    fi
}

hyprx_gate_internet_probe() {
    # The distro mirror, not a generic host: what matters is whether pacman can
    # reach its own databases. 443 is the port the official mirrorlist uses.
    local host="archlinux.org" port=443

    # 1. bash's /dev/tcp. No external binary, so it works in a container.
    if ( exec 3<>"/dev/tcp/$host/$port" ) 2>/dev/null; then
        exec 3<&- 2>/dev/null
        exec 3>&- 2>/dev/null
        printf 'ok'
        return 0
    fi

    # 2. curl
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 5 -o /dev/null "https://$host/" 2>/dev/null; then
            printf 'ok'
            return 0
        fi
        printf 'down'
        return 0
    fi

    # 3. wget
    if command -v wget >/dev/null 2>&1; then
        if wget -q --spider --timeout=5 "https://$host/" 2>/dev/null; then
            printf 'ok'
            return 0
        fi
        printf 'down'
        return 0
    fi

    # 4. ping, last: ICMP is frequently blocked where HTTPS is not, so a
    #    ping failure here is weak evidence of anything.
    if command -v ping >/dev/null 2>&1; then
        if ping -c1 -W2 "$host" >/dev/null 2>&1; then
            printf 'ok'
            return 0
        fi
        printf 'down'
        return 0
    fi

    # No probe available at all. Unknown is not down.
    printf 'unknown'
}

# `hyprx_gate_internet` - a boolean wrapper over the state function - used to
# live here and had no callers, so it is gone rather than maintained as an API
# that nothing exercises. `hyprx_gate_internet_state` is the interface.

# `sudo -v` refreshes the credential cache; `sudo -n true` only tests it.
#
# Prefer the non-interactive probe so a cached ticket is detected without a
# prompt, and fall back to `sudo -v` so a first-time TTY run still validates.
# Whichever answers first is remembered - this used to be called twice, once per
# file.
hyprx_gate_sudo() {
    # `sudo -n true` prints nothing and signals success through its exit status.
    # hyprx_gate_probe returns a value, not a status - it captures stdout - so it
    # cannot tell "succeeded silently" from "failed silently". A dedicated flag
    # carries the status instead, and gates the work at one run.
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

# `df --output=avail <path>` -> the free-space number alone. Kept separate so
# the CACHE stores the trimmed value rather than the header line plus the value:
# caching is done by hyprx_gate_probe, which sees only stdout, so any cleanup
# has to happen before it.
hyprx_gate_disk_probe() {
    df --output=avail "$1" 2>/dev/null | tail -n1 | tr -d ' '
}

# Free space in KiB, stored in <varname>.
#
# Also a destination argument rather than a printed one: the gate used to call
# this as `root_kb="$(hyprx_gate_disk_kb /)"`, and that subshell is where the
# cache write went to die.
hyprx_gate_disk_kb() {
    local __hyprx_path="$1"
    local __hyprx_dest="$2"
    hyprx_gate_probe "disk_$__hyprx_path" "$__hyprx_dest" \
        hyprx_gate_disk_probe "$__hyprx_path"
}

# Free RAM in MiB, stored in <varname>.
hyprx_gate_ram_mb() {
    # One read, one unit. The old pair divided the same value by 1024/1024 in
    # one file and by 1024 in the other, so "8GB" was compared against gigabytes
    # and "4GB" against megabytes.
    # Single-quoted: $2 is awk's field reference, not a shell variable. The
    # directive must sit directly above the awk command - it applies to the next
    # command only, so a blank line or a `local` between them stops it covering
    # the string it was written for.
    # shellcheck disable=SC2016
    hyprx_gate_probe ram "$1" awk '/^MemTotal:/ {print int($2/1024); exit}' /proc/meminfo
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
    # Three states, not two. "unknown" means no probe tool was available, which
    # is emphatically not evidence of a broken network - and treating it as one
    # aborted every install in a minimal container, because ping ships in
    # iputils and nothing here depends on that.
    #
    # Assigned, not `case "$(hyprx_gate_internet_state)"`: the substitution is a
    # subshell, and the probe cache written inside it would be discarded the
    # moment it exited.
    local net_state
    hyprx_gate_internet_state net_state
    case "$net_state" in
        ok)
            gate_result ok "Network reachable (archlinux.org)"
            ;;
        unknown)
            gate_result warn "Could not verify network reachability" \
                "No probe available (bash /dev/tcp, curl, wget and ping all absent)."
            ;;
        *)
            if $dry; then
                gate_result warn "Network unreachable - a real install would need this"
            else
                gate_result error "Network unreachable" \
                    "Package databases cannot be synchronised. Check your connection or mirrors."
            fi
            ;;
    esac

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
    hyprx_gate_disk_kb / root_kb
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
    hyprx_gate_disk_kb "$HOME" home_kb
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
    hyprx_gate_ram_mb ram_mb
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
    hyprx_gate_probe threads threads nproc
    [[ -n "$threads" ]] && hyprx_ui_info "CPU: $threads threads"

    if [[ "$HYPRX_DETECT_GPU_VENDOR" == "nvidia" ]] \
       && [[ ! -f /sys/module/nvidia_drm/parameters/modeset ]]; then
        gate_result warn "nvidia_drm.modeset is not enabled" \
            "GPU offload setup will warn. See the comment in config/hypr/env.lua."
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
