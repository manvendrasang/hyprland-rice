#!/usr/bin/env bash

########################################
# Snapshot storage locations
########################################

HYPRX_SNAPSHOT_DIR="${HYPRX_SNAPSHOT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/snapshots}"

HYPRX_SNAPSHOT_CONFIG_BACKUPS=()

########################################
# Shared snapshot id for this install run
########################################

HYPRX_SNAPSHOT_CURRENT_ID=""

########################################
# Initialize the snapshot id for this run
########################################

hyprx_snapshot_init_id() {

    HYPRX_SNAPSHOT_CURRENT_ID="$(date +%Y%m%d-%H%M%S)"

}

########################################
# Read the current snapshot id
########################################

hyprx_snapshot_current_id() {

    if [[ -z "$HYPRX_SNAPSHOT_CURRENT_ID" ]]; then
        hyprx_ui_warn "hyprx_snapshot_current_id read before hyprx_snapshot_init_id was called"
        hyprx_snapshot_init_id
    fi

    echo "$HYPRX_SNAPSHOT_CURRENT_ID"

}

########################################
# Config backup root
########################################

hyprx_snapshot_backup_root() {

    echo "${HYPRX_CONFIG_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/config-backups}"

}

hyprx_snapshot_backup_dir_for() {

    echo "$(hyprx_snapshot_backup_root)/$1"

}

########################################
# Record that a config dir was touched
########################################

hyprx_snapshot_record_config() {

    HYPRX_SNAPSHOT_CONFIG_BACKUPS+=("$1:$2")

}

########################################
# Save a snapshot of this install run
########################################

hyprx_snapshot_save() {

    # Nothing was changed by a dry run, so there is nothing to roll back.
    # Writing a snapshot here would also pollute `hyprx rollback list`
    # with an entry that would remove packages the user still has.
    hyprx_util_dry_run && return 0

    mkdir -p "$HYPRX_SNAPSHOT_DIR"

    if (( ${#HYPRX_INSTALL_INSTALLED[@]} == 0 )) && (( ${#HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]} == 0 )); then
        return 0
    fi

    local id
    id="$(hyprx_snapshot_current_id)"

    local file="$HYPRX_SNAPSHOT_DIR/$id.snapshot"

    {
        echo "DATE=$(date)"
        echo "PACKAGES=${#HYPRX_INSTALL_INSTALLED[@]}"
        echo "CONFIGS=${#HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]}"
        echo "---PACKAGES---"
        printf "%s\n" "${HYPRX_INSTALL_INSTALLED[@]}"
        echo "---CONFIGS---"
        printf "%s\n" "${HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]}"
    } > "$file"

    hyprx_ui_info "Snapshot saved: $id"

    HYPRX_SNAPSHOT_LAST_ID="$id"

}

########################################
# List available snapshots
########################################

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

########################################
# Snapshot exists?
########################################

hyprx_snapshot_exists() {

    [[ -f "$HYPRX_SNAPSHOT_DIR/$1.snapshot" ]]

}

########################################
# Deployed-targets state file
########################################

HYPRX_DEPLOYED_TARGETS_FILE="${HYPRX_DEPLOYED_TARGETS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/deployed-targets}"

########################################
# Read the previously deployed targets
########################################

hyprx_snapshot_read_deployed() {

    [[ -f "$HYPRX_DEPLOYED_TARGETS_FILE" ]] || return 0

    cat "$HYPRX_DEPLOYED_TARGETS_FILE"

}

########################################
# Persist the currently deployed targets
########################################

hyprx_snapshot_write_deployed() {

    mkdir -p "$(dirname "$HYPRX_DEPLOYED_TARGETS_FILE")"

    printf "%s\n" "$@" > "$HYPRX_DEPLOYED_TARGETS_FILE"

}

########################################
# Get package list from a snapshot
########################################

hyprx_snapshot_packages() {

    local id="$1"
    local file="$HYPRX_SNAPSHOT_DIR/$id.snapshot"

    [[ -f "$file" ]] || return 1

    sed -n '/^---PACKAGES---$/,/^---CONFIGS---$/p' "$file" | sed '1d;$d'

}

########################################
# Get config backup entries from a snapshot
########################################

hyprx_snapshot_configs() {

    local id="$1"
    local file="$HYPRX_SNAPSHOT_DIR/$id.snapshot"

    [[ -f "$file" ]] || return 1

    sed -n '/^---CONFIGS---$/,$p' "$file" | sed '1d'

}

########################################
# Most recent snapshot id
########################################

hyprx_snapshot_latest() {

    [[ -d "$HYPRX_SNAPSHOT_DIR" ]] || return 1

    find "$HYPRX_SNAPSHOT_DIR" -maxdepth 1 -name "*.snapshot" -printf '%f\n' 2>/dev/null \
        | sed 's/\.snapshot$//' \
        | sort \
        | tail -n1

}

########################################
# Delete a snapshot (after successful rollback)
########################################

hyprx_snapshot_remove() {

    local id="$1"
    local file="$HYPRX_SNAPSHOT_DIR/$id.snapshot"

    [[ -f "$file" ]] && rm -f "$file"

    rm -rf "$(hyprx_snapshot_backup_dir_for "$id")"

}

########################################
# Restore (or remove) a single config dir
########################################

hyprx_snapshot_restore_config() {

    local id="$1"
    local dir="$2"
    local existed="$3"

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

########################################
# Roll back a snapshot
########################################

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

    local failed=0

    ####################################
    # Packages
    ####################################

    local pkg

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

    ####################################
    # Configs
    ####################################

    local entry dir existed

    while IFS= read -r entry; do

        [[ -z "$entry" ]] && continue

        dir="${entry%%:*}"
        existed="${entry##*:}"

        hyprx_snapshot_restore_config "$id" "$dir" "$existed" || failed=1

    done < <(hyprx_snapshot_configs "$id")

    ####################################
    # Result
    ####################################

    if (( failed == 0 )); then
        hyprx_snapshot_remove "$id"
        hyprx_ui_success "Rollback complete. Snapshot $id removed."
    else
        hyprx_ui_warn "Rollback finished with errors. Snapshot $id retained."
    fi

    return "$failed"

}
