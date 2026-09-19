#!/usr/bin/env bash

########################################
# Config directories to deploy
########################################

HYPRX_CONFIG_TARGETS="hypr waybar wlogout swaync swappy rofi waypaper"

########################################
# Deploy a single config directory
########################################
#
# Backs up whatever already exists at the
# target before overwriting it, and records
# the outcome so rollback can undo it later.
#

deploy_config_dir() {

    local dir="$1"

    local source="$HYPRX_CONFIG/$dir"
    local target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"
    local staging="${target}.hyprx-staging.$$"

    if [[ ! -d "$source" ]]; then
        warn "Missing config source: $dir"
        return 1
    fi

    mkdir -p "$(dirname "$target")"

    # Build the full new config in a staging dir first. This can take
    # real time for large configs, so it must never happen with the
    # live target already removed - a config watcher (e.g. Hyprland's
    # live reload) could catch the target mid-copy or briefly missing.
    rm -rf "$staging"
    cp -r "$source" "$staging"

    if [[ -e "$target" ]]; then

        local backup
        backup="$(config_backup_dir_for "$(current_snapshot_id)")/$dir"

        mkdir -p "$(dirname "$backup")"
        rm -rf "$backup"

        # Swap: two fast renames instead of rm-then-copy, so the
        # target is only ever missing for a moment, not seconds.
        mv "$target" "$backup"
        mv "$staging" "$target"

        record_config_backup "$dir" "true"

        info "Backed up existing $dir"

    else

        mv "$staging" "$target"

        record_config_backup "$dir" "false"

    fi

    success "Deployed $dir"

    # swaync ships a systemd user service, enabled by the package's
    # own preset, that races against this rice's own exec_cmd("swaync")
    # autostart (config/hypr/hyprland.lua) - whichever wins launches
    # fine, the other hits "instance already running", exits 1, and
    # systemd burns through 5 retries before giving up
    # (start-limit-hit). Harmless (swaync ends up running either way)
    # but noisy and pointless. This rice always launches session
    # daemons via exec_cmd, never systemd --user units, so disable the
    # redundant path rather than the one this rice actually relies on.
    if [[ "$dir" == "swaync" ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable swaync.service >/dev/null 2>&1 || true
    fi

}

########################################
# Remove targets no longer deployed
########################################
#
# Compares the targets deployed by the
# previous install run (DEPLOYED_TARGETS_FILE)
# against the current HYPRX_CONFIG_TARGETS.
# Anything deployed before but missing from
# the list now (a feature/theme was removed)
# gets backed up and removed the same way an
# in-place redeploy backs up an overwritten
# dir - so it is restorable via rollback,
# never just silently deleted.
#

remove_orphaned_targets() {

    local previous
    previous="$(read_deployed_targets)"

    [[ -z "$previous" ]] && return 0

    local dir target backup

    for dir in $previous; do

        # Still a current target - nothing to do.
        if printf '%s\n' $HYPRX_CONFIG_TARGETS | grep -qx "$dir"; then
            continue
        fi

        target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"

        [[ -e "$target" ]] || continue

        backup="$(config_backup_dir_for "$(current_snapshot_id)")/$dir"

        mkdir -p "$(dirname "$backup")"
        rm -rf "$backup"
        mv "$target" "$backup"

        record_config_backup "$dir" "true"

        info "Removed orphaned config: $dir (no longer a deploy target)"

    done

}

########################################
# Deploy every configured directory
########################################

deploy_configs() {

    section "Deploying configuration"

    local dir

    for dir in $HYPRX_CONFIG_TARGETS; do
        deploy_config_dir "$dir"
    done

    remove_orphaned_targets

    write_deployed_targets $HYPRX_CONFIG_TARGETS

}
