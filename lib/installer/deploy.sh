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

    for dir in $previous; do
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
    for dir in $HYPRX_CONFIG_TARGETS; do
        hyprx_deploy_config_dir "$dir"
    done

    hyprx_deploy_remove_orphaned

    # Drives the next run's orphan detection - writing it during a dry run
    # would make that run believe targets it never deployed were deployed.
    if hyprx_util_dry_run; then
        hyprx_util_would "record deploy targets for the next run"
    else
        hyprx_snapshot_write_deployed $HYPRX_CONFIG_TARGETS
    fi
}
