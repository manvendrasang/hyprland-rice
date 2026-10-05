#!/usr/bin/env bash

HYPRX_CONFIG_TARGETS="hypr waybar wlogout swaync swappy rofi waypaper wallust gtk-3.0"

hyprx_deploy_config_dir() {
    local dir="$1"
    local source="$HYPRX_CONFIG/$dir"
    local target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"
    local staging="${target}.hyprx-staging.$$"

    # Dots are allowed: "gtk-3.0" is a real target. Block only names that could
    # escape the target - a path separator or a relative segment.
    if [[ "$dir" =~ [/] ]] || [[ "$dir" == "." ]] || [[ "$dir" == ".." ]] \
       || [[ ! "$dir" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        hyprx_ui_error "Invalid config directory name: $dir"
        return 1
    fi

    if [[ ! -d "$source" ]]; then
        hyprx_ui_warn "Missing config source: $dir"
        return 1
    fi

    # After the checks above, so a dry run still surfaces a bad source.
    if hyprx_util_dry_run; then
        if [[ -e "$target" ]]; then
            hyprx_util_would "back up existing $dir, then deploy $dir -> $target"
        else
            hyprx_util_would "deploy $dir -> $target (new)"
        fi
        return 0
    fi

    mkdir -p "$(dirname "$target")"

    # A live hyprpaper.conf is runtime state owned by
    # scripts/sync-hyprpaper-conf.sh, not a template. Capture it before the
    # swap, and outside the target dir - a temp file inside would be moved into
    # the backup along with everything else.
    local preserved_conf=""
    if [[ "$dir" == "hypr" && -f "${target}/hyprpaper.conf" ]] \
       && grep -q '^wallpaper' "${target}/hyprpaper.conf" 2>/dev/null; then
        preserved_conf="$(dirname "$target")/.hyprpaper.conf.preserved.$$"
        cp "${target}/hyprpaper.conf" "$preserved_conf" 2>/dev/null || preserved_conf=""
    fi

    # waypaper records the last wallpaper it applied in its own config.ini, and
    # the repo copy has no wallpaper key on purpose. Deploying it verbatim used
    # to wipe that key, so `waypaper --restore` could not work after an install
    # and silently fell back to a random wallpaper. Same treatment as
    # hyprpaper.conf above: capture the live value, restore it after the swap.
    local preserved_wallpaper=""
    if [[ "$dir" == "waypaper" && -f "${target}/config.ini" ]]; then
        preserved_wallpaper="$(sed -n 's/^wallpaper[[:space:]]*=[[:space:]]*//p' \
            "${target}/config.ini" 2>/dev/null | head -n1)"
        if [[ -n "$preserved_wallpaper" ]]; then
            preserved_wallpaper="$(dirname "$target")/.waypaper-wallpaper.preserved.$$"
            sed -n 's/^wallpaper[[:space:]]*=[[:space:]]*//p' "${target}/config.ini" 2>/dev/null \
                | head -n1 >"$preserved_wallpaper" || preserved_wallpaper=""
        fi
    fi

    # Stage first: copying a large config with the live target already removed
    # leaves it missing for seconds, which a config watcher can catch.
    rm -rf "$staging"
    cp -r "$source" "$staging"

    if [[ -e "$target" ]]; then
        if hyprx_config_bool HYPRX_CONFIG_BACKUP_ON_DEPLOY; then
            local backup
            backup="$(hyprx_snapshot_backup_dir_for "$(hyprx_snapshot_current_id)")/$dir"

            mkdir -p "$(dirname "$backup")"
            rm -rf "$backup"

            # Two renames rather than rm-then-copy: the target is only ever
            # missing for a moment.
            mv "$target" "$backup"
            mv "$staging" "$target"

            hyprx_snapshot_record_config "$dir" "true"
            hyprx_ui_info "Backed up existing $dir"
        else
            # Recorded as existed=true even with no copy, so a rollback reports
            # "cannot restore" rather than pretending it was a fresh deploy.
            rm -rf "$target"
            mv "$staging" "$target"

            hyprx_snapshot_record_config "$dir" "true"
            hyprx_ui_warn "Replaced existing $dir with no backup (BACKUP_ON_DEPLOY=false) - hyprx rollback cannot restore it"
        fi
    else
        mv "$staging" "$target"
        hyprx_snapshot_record_config "$dir" "false"
    fi

    hyprx_ui_success "Deployed $dir"

    if [[ -n "$preserved_conf" && -f "$preserved_conf" ]]; then
        mv "$preserved_conf" "${target}/hyprpaper.conf"
        hyprx_ui_info "Preserved live hyprpaper.conf (wallpaper path kept)"
    fi

    if [[ -n "$preserved_wallpaper" && -f "$preserved_wallpaper" ]]; then
        # Rewrite the key in place rather than replacing the file, so any other
        # setting the user added to config.ini survives the deploy.
        sed -i "s|^wallpaper[[:space:]]*=.*|wallpaper = $(cat "$preserved_wallpaper")|" \
            "${target}/config.ini" 2>/dev/null || true
        rm -f "$preserved_wallpaper"
        hyprx_ui_info "Preserved live waypaper wallpaper (waypaper --restore still works)"
    fi

    # The swaync package enables a systemd user service that races this rice's
    # exec_cmd("swaync") autostart - the loser exits 1 and systemd burns five
    # retries. Daemons here always launch via exec_cmd, so disable the
    # redundant unit.
    if [[ "$dir" == "swaync" ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable swaync.service >/dev/null 2>&1 || true
    fi
}

# Targets dropped from HYPRX_CONFIG_TARGETS, moved aside so a rollback can
# restore them.
hyprx_deploy_remove_orphaned() {
    local previous
    previous="$(hyprx_snapshot_read_deployed)"

    [[ -z "$previous" ]] && return 0

    local dir target backup

    # Deliberate word-splitting: both HYPRX_CONFIG_TARGETS and the contents of
    # deployed-targets are space-separated lists of directory names, not arrays.
    # Every name has already passed the [a-zA-Z0-9._-] check in
    # hyprx_deploy_config_dir, so there is nothing here for a glob to match.
    # shellcheck disable=SC2086
    for dir in $previous; do
        # shellcheck disable=SC2086
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

hyprx_deploy_all() {
    hyprx_ui_section "Deploying configuration"

    local dir
    local -a failed=()

    # Deliberate word-splitting: HYPRX_CONFIG_TARGETS is a space-separated list
    # of directory names, not an array. Each is validated by
    # hyprx_deploy_config_dir before anything is written.
    # shellcheck disable=SC2086
    for dir in $HYPRX_CONFIG_TARGETS; do
        # Each target's status has to be collected. The loop used to ignore it,
        # and the function then fell off the end returning the status of its
        # last statement - so `hyprx_deploy_all || return 1` in engine.sh was
        # dead code, and a config dir that failed to deploy (a missing source in
        # a partial clone, say) still produced "Installation completed
        # successfully" at the end of the run.
        if ! hyprx_deploy_config_dir "$dir"; then
            failed+=("$dir")
            hyprx_event config.failed target="$dir"
        else
            hyprx_event config.deployed target="$dir"
        fi
    done

    hyprx_deploy_remove_orphaned

    # Drives the next run's orphan detection - writing it during a dry run
    # would make that run believe targets it never deployed were deployed.
    if hyprx_util_dry_run; then
        hyprx_util_would "record deploy targets for the next run"
    else
        # One argument per target; the function writes them one per line.
        # shellcheck disable=SC2086
        hyprx_snapshot_write_deployed $HYPRX_CONFIG_TARGETS
    fi

    if (( ${#failed[@]} > 0 )); then
        hyprx_ui_error "Config deploy failed for: ${failed[*]}"
        hyprx_ui_info "Those directories were not written. Fix them, then re-run 'hyprx install'."
        return 1
    fi

    return 0
}
