#!/usr/bin/env bash

########################################
# Config directories to deploy
########################################

HYPRX_CONFIG_TARGETS="hypr waybar wlogout swaync swappy rofi waypaper wallust gtk-3.0"

########################################
# Deploy a single config directory
########################################

hyprx_deploy_config_dir() {

    local dir="$1"

    local source="$HYPRX_CONFIG/$dir"
    local target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"
    local staging="${target}.hyprx-staging.$$"

    # Validate directory name to prevent path traversal.
    #
    # Dots are deliberately ALLOWED: a real target in HYPRX_CONFIG_TARGETS is
    # "gtk-3.0", and an earlier `[^a-zA-Z0-9_-]` check rejected it - so that
    # config directory was silently never deployed, on every install, with only
    # a one-line error scrolling past. What actually needs blocking is a name
    # that can escape the target: any path separator, or a relative segment.
    if [[ "$dir" =~ [/] ]] || [[ "$dir" == "." ]] || [[ "$dir" == ".." ]] \
       || [[ ! "$dir" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        hyprx_ui_error "Invalid config directory name: $dir"
        return 1
    fi

    if [[ ! -d "$source" ]]; then
        hyprx_ui_warn "Missing config source: $dir"
        return 1
    fi

    # Report the plan and touch nothing. Deliberately placed after the
    # validation checks above so a dry run still surfaces a missing or
    # malformed source, and after the target-exists probe so it can say
    # whether a backup would be taken.
    if hyprx_util_dry_run; then
        if [[ -e "$target" ]]; then
            hyprx_util_would "back up existing $dir, then deploy $dir -> $target"
        else
            hyprx_util_would "deploy $dir -> $target (new)"
        fi
        return 0
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
        backup="$(hyprx_snapshot_backup_dir_for "$(hyprx_snapshot_current_id)")/$dir"

        mkdir -p "$(dirname "$backup")"
        rm -rf "$backup"

        # Swap: two fast renames instead of rm-then-copy, so the
        # target is only ever missing for a moment, not seconds.
        mv "$target" "$backup"
        mv "$staging" "$target"

        hyprx_snapshot_record_config "$dir" "true"

        hyprx_ui_info "Backed up existing $dir"

    else

        mv "$staging" "$target"

        hyprx_snapshot_record_config "$dir" "false"

    fi

    hyprx_ui_success "Deployed $dir"

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

hyprx_deploy_remove_orphaned() {

    local previous
    previous="$(hyprx_snapshot_read_deployed)"

    [[ -z "$previous" ]] && return 0

    local dir target backup

    for dir in $previous; do

        # Still a current target - nothing to do.
        if printf '%s\n' $HYPRX_CONFIG_TARGETS | grep -qx "$dir"; then
            continue
        fi

        target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"

        [[ -e "$target" ]] || continue

        if hyprx_util_dry_run; then
            hyprx_util_would "move orphaned config $dir out of $target (no longer a deploy target)"
            continue
        fi

        backup="$(hyprx_snapshot_backup_dir_for "$(hyprx_snapshot_current_id)")/$dir"

        mkdir -p "$(dirname "$backup")"
        rm -rf "$backup"
        mv "$target" "$backup"

        hyprx_snapshot_record_config "$dir" "true"

        hyprx_ui_info "Removed orphaned config: $dir (no longer a deploy target)"

    done

}

########################################
# Deploy every configured directory
########################################

hyprx_deploy_all() {

    hyprx_ui_section "Deploying configuration"

    local dir

    for dir in $HYPRX_CONFIG_TARGETS; do
        hyprx_deploy_config_dir "$dir"
    done

    hyprx_deploy_remove_orphaned

    # This file drives the next run's orphan detection. Writing it during a
    # dry run would make the *next* real run believe targets it never
    # deployed were already deployed, so it must be skipped.
    if hyprx_util_dry_run; then
        hyprx_util_would "record deploy targets for the next run"
    else
        hyprx_snapshot_write_deployed $HYPRX_CONFIG_TARGETS
    fi

}
