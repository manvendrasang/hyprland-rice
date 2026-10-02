#!/usr/bin/env bash

HYPRX_SNAPSHOT_DIR="$HYPRX_STATE_SNAPSHOT_DIR"
HYPRX_DEPLOYED_TARGETS_FILE="$HYPRX_STATE_DEPLOYED_FILE"

HYPRX_SNAPSHOT_CONFIG_BACKUPS=()
HYPRX_SNAPSHOT_CURRENT_ID=""

hyprx_snapshot_init_id() {
    HYPRX_SNAPSHOT_CURRENT_ID="$(date +%Y%m%d-%H%M%S)"
}

hyprx_snapshot_current_id() {
    if [[ -z "$HYPRX_SNAPSHOT_CURRENT_ID" ]]; then
        hyprx_ui_warn "hyprx_snapshot_current_id read before hyprx_snapshot_init_id was called"
        hyprx_snapshot_init_id
    fi

    echo "$HYPRX_SNAPSHOT_CURRENT_ID"
}

hyprx_snapshot_backup_root() {
    echo "$HYPRX_STATE_BACKUP_DIR"
}

hyprx_snapshot_backup_dir_for() {
    echo "$(hyprx_snapshot_backup_root)/$1"
}

# Records "<dir>:<existed-before-deploy>", which is what a rollback reads.
hyprx_snapshot_record_config() {
    HYPRX_SNAPSHOT_CONFIG_BACKUPS+=("$1:$2")
}

hyprx_snapshot_save() {
    # A dry run changed nothing, so there is nothing to roll back - and a
    # snapshot here would offer to remove packages the user still has.
    hyprx_util_dry_run && return 0

    mkdir -p "$HYPRX_SNAPSHOT_DIR"

    if (( ${#HYPRX_INSTALL_INSTALLED[@]} == 0 )) && (( ${#HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]} == 0 )); then
        return 0
    fi

    local id file
    id="$(hyprx_snapshot_current_id)"
    file="$HYPRX_SNAPSHOT_DIR/$id.snapshot"

    {
        echo "DATE=$(date)"
        echo "PACKAGES=${#HYPRX_INSTALL_INSTALLED[@]}"
        echo "CONFIGS=${#HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]}"
        echo "---PACKAGES---"
        printf "%s\n" "${HYPRX_INSTALL_INSTALLED[@]}"
        echo "---CONFIGS---"
        printf "%s\n" "${HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]}"
    } >"$file"

    hyprx_ui_info "Snapshot saved: $id"

    HYPRX_SNAPSHOT_LAST_ID="$id"
}

hyprx_snapshot_list() {
    [[ -d "$HYPRX_SNAPSHOT_DIR" ]] || return 0

    local file id date pkg_count cfg_count

    for file in "$HYPRX_SNAPSHOT_DIR"/*.snapshot; do
        [[ -f "$file" ]] || continue

        id="$(basename "$file" .snapshot)"
        date="$(grep '^DATE=' "$file" | cut -d= -f2-)"
        pkg_count="$(grep '^PACKAGES=' "$file" | cut -d= -f2-)"
        cfg_count="$(grep '^CONFIGS=' "$file" | cut -d= -f2-)"

        printf "%-16s  %-4s pkgs  %-4s configs  %s\n" \
            "$id" "$pkg_count" "$cfg_count" "$date"
    done
}

hyprx_snapshot_exists() {
    [[ -f "$HYPRX_SNAPSHOT_DIR/$1.snapshot" ]]
}

hyprx_snapshot_read_deployed() {
    [[ -f "$HYPRX_DEPLOYED_TARGETS_FILE" ]] || return 0

    cat "$HYPRX_DEPLOYED_TARGETS_FILE"
}

hyprx_snapshot_write_deployed() {
    mkdir -p "$(dirname "$HYPRX_DEPLOYED_TARGETS_FILE")"

    printf "%s\n" "$@" >"$HYPRX_DEPLOYED_TARGETS_FILE"
}

hyprx_snapshot_packages() {
    local file="$HYPRX_SNAPSHOT_DIR/$1.snapshot"

    [[ -f "$file" ]] || return 1

    sed -n '/^---PACKAGES---$/,/^---CONFIGS---$/p' "$file" | sed '1d;$d'
}

hyprx_snapshot_configs() {
    local file="$HYPRX_SNAPSHOT_DIR/$1.snapshot"

    [[ -f "$file" ]] || return 1

    sed -n '/^---CONFIGS---$/,$p' "$file" | sed '1d'
}

hyprx_snapshot_latest() {
    [[ -d "$HYPRX_SNAPSHOT_DIR" ]] || return 1

    find "$HYPRX_SNAPSHOT_DIR" -maxdepth 1 -name "*.snapshot" -printf '%f\n' 2>/dev/null \
        | sed 's/\.snapshot$//' \
        | sort \
        | tail -n1
}

hyprx_snapshot_remove() {
    local id="$1"

    [[ -f "$HYPRX_SNAPSHOT_DIR/$id.snapshot" ]] && rm -f "$HYPRX_SNAPSHOT_DIR/$id.snapshot"

    rm -rf "$(hyprx_snapshot_backup_dir_for "$id")"
}

hyprx_snapshot_restore_config() {
    local id="$1" dir="$2" existed="$3"
    local target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"
    local backup
    backup="$(hyprx_snapshot_backup_dir_for "$id")/$dir"

    if [[ "$existed" == "true" ]]; then
        if [[ ! -d "$backup" ]]; then
            hyprx_ui_error "Missing backup for $dir, cannot restore"
            return 1
        fi

        rm -rf "$target"
        cp -r "$backup" "$target"
        hyprx_ui_success "Restored $dir"
    else
        rm -rf "$target"
        hyprx_ui_success "Removed $dir (was newly deployed)"
    fi
}

hyprx_snapshot_rollback() {
    local id="$1"

    if ! hyprx_util_validate_snapshot_id "$id"; then
        hyprx_ui_error "Invalid snapshot ID format: $id"
        return 1
    fi

    if ! hyprx_snapshot_exists "$id"; then
        hyprx_ui_error "No such snapshot: $id"
        return 1
    fi

    local failed=0 pkg entry dir existed

    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue

        hyprx_ui_info "Removing $pkg"

        if hyprx_pkg_remove "$pkg"; then
            hyprx_ui_success "$pkg"
        else
            hyprx_ui_error "$pkg"
            failed=1
        fi
    done < <(hyprx_snapshot_packages "$id")

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue

        dir="${entry%%:*}"
        existed="${entry##*:}"

        hyprx_snapshot_restore_config "$id" "$dir" "$existed" || failed=1
    done < <(hyprx_snapshot_configs "$id")

    # Only discard the snapshot once everything succeeded - otherwise it is the
    # user's only route to retrying.
    if (( failed == 0 )); then
        hyprx_snapshot_remove "$id"
        hyprx_ui_success "Rollback complete. Snapshot $id removed."
    else
        hyprx_ui_warn "Rollback finished with errors. Snapshot $id retained."
    fi

    return "$failed"
}
