#!/usr/bin/env bash

########################################
# Snapshot storage locations
########################################

SNAPSHOT_DIR="${HYPRX_SNAPSHOT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/snapshots}"

CONFIG_BACKUPS=()

########################################
# Shared snapshot id for this install run
########################################
#
# Packages and config backups from the
# same install run share one id, so a
# single rollback undoes both together.
#

CURRENT_SNAPSHOT_ID=""

current_snapshot_id() {

    if [[ -z "$CURRENT_SNAPSHOT_ID" ]]; then
        CURRENT_SNAPSHOT_ID="$(date +%Y%m%d-%H%M%S)"
    fi

    echo "$CURRENT_SNAPSHOT_ID"

}

########################################
# Config backup root
########################################

config_backup_root() {

    echo "${HYPRX_CONFIG_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/config-backups}"

}

config_backup_dir_for() {

    echo "$(config_backup_root)/$1"

}

########################################
# Record that a config dir was touched
########################################
#
# existed = true  -> a backup was made, restore it on rollback
# existed = false -> nothing existed before, remove it on rollback
#

record_config_backup() {

    CONFIG_BACKUPS+=("$1:$2")

}

########################################
# Save a snapshot of this install run
########################################
#
# Records packages newly installed this
# run (INSTALLED_PACKAGES) and any config
# directories touched by deploy_configs
# (CONFIG_BACKUPS). Already-present
# packages and untouched configs are
# never recorded, so rollback can never
# affect anything HyprX didn't change.
#

save_snapshot() {

    mkdir -p "$SNAPSHOT_DIR"

    if (( ${#INSTALLED_PACKAGES[@]} == 0 )) && (( ${#CONFIG_BACKUPS[@]} == 0 )); then
        return 0
    fi

    local id
    id="$(current_snapshot_id)"

    local file="$SNAPSHOT_DIR/$id.snapshot"

    {
        echo "PROFILE=${PROFILE:-unknown}"
        echo "DATE=$(date)"
        echo "PACKAGES=${#INSTALLED_PACKAGES[@]}"
        echo "CONFIGS=${#CONFIG_BACKUPS[@]}"
        echo "---PACKAGES---"
        printf "%s\n" "${INSTALLED_PACKAGES[@]}"
        echo "---CONFIGS---"
        printf "%s\n" "${CONFIG_BACKUPS[@]}"
    } > "$file"

    info "Snapshot saved: $id"

    LAST_SNAPSHOT_ID="$id"

}

########################################
# List available snapshots
########################################

list_snapshots() {

    [[ -d "$SNAPSHOT_DIR" ]] || return 0

    local file id profile date pkg_count cfg_count

    for file in "$SNAPSHOT_DIR"/*.snapshot; do

        [[ -f "$file" ]] || continue

        id="$(basename "$file" .snapshot)"
        profile="$(grep '^PROFILE=' "$file" | cut -d= -f2-)"
        date="$(grep '^DATE=' "$file" | cut -d= -f2-)"
        pkg_count="$(grep '^PACKAGES=' "$file" | cut -d= -f2-)"
        cfg_count="$(grep '^CONFIGS=' "$file" | cut -d= -f2-)"

        printf "%-16s  %-12s  %-4s pkgs  %-4s configs  %s\n" \
            "$id" "$profile" "$pkg_count" "$cfg_count" "$date"

    done

}

########################################
# Snapshot exists?
########################################

snapshot_exists() {

    [[ -f "$SNAPSHOT_DIR/$1.snapshot" ]]

}

########################################
# Get package list from a snapshot
########################################

snapshot_packages() {

    local id="$1"
    local file="$SNAPSHOT_DIR/$id.snapshot"

    [[ -f "$file" ]] || return 1

    sed -n '/^---PACKAGES---$/,/^---CONFIGS---$/p' "$file" | sed '1d;$d'

}

########################################
# Get config backup entries from a snapshot
########################################

snapshot_configs() {

    local id="$1"
    local file="$SNAPSHOT_DIR/$id.snapshot"

    [[ -f "$file" ]] || return 1

    sed -n '/^---CONFIGS---$/,$p' "$file" | sed '1d'

}

########################################
# Most recent snapshot id
########################################

latest_snapshot() {

    [[ -d "$SNAPSHOT_DIR" ]] || return 1

    find "$SNAPSHOT_DIR" -maxdepth 1 -name "*.snapshot" -printf '%f\n' 2>/dev/null \
        | sed 's/\.snapshot$//' \
        | sort \
        | tail -n1

}

########################################
# Delete a snapshot (after successful rollback)
########################################

remove_snapshot() {

    local id="$1"
    local file="$SNAPSHOT_DIR/$id.snapshot"

    [[ -f "$file" ]] && rm -f "$file"

    rm -rf "$(config_backup_dir_for "$id")"

}

########################################
# Restore (or remove) a single config dir
########################################

restore_config_dir() {

    local id="$1"
    local dir="$2"
    local existed="$3"

    local target="${HYPRX_TARGET_HOME:-$HOME}/.config/$dir"
    local backup
    backup="$(config_backup_dir_for "$id")/$dir"

    if [[ "$existed" == "true" ]]; then

        if [[ ! -d "$backup" ]]; then
            error "Missing backup for $dir, cannot restore"
            return 1
        fi

        rm -rf "$target"
        cp -r "$backup" "$target"
        success "Restored $dir"

    else

        rm -rf "$target"
        success "Removed $dir (was newly deployed)"

    fi

}

########################################
# Roll back a snapshot
########################################

rollback_snapshot() {

    local id="$1"

    if ! snapshot_exists "$id"; then
        error "No such snapshot: $id"
        return 1
    fi

    local failed=0

    ####################################
    # Packages
    ####################################

    local pkg

    while IFS= read -r pkg; do

        [[ -z "$pkg" ]] && continue

        info "Removing $pkg"

        if remove_package "$pkg"; then
            success "$pkg"
        else
            error "$pkg"
            failed=1
        fi

    done < <(snapshot_packages "$id")

    ####################################
    # Configs
    ####################################

    local entry dir existed

    while IFS= read -r entry; do

        [[ -z "$entry" ]] && continue

        dir="${entry%%:*}"
        existed="${entry##*:}"

        restore_config_dir "$id" "$dir" "$existed" || failed=1

    done < <(snapshot_configs "$id")

    ####################################
    # Result
    ####################################

    if (( failed == 0 )); then
        remove_snapshot "$id"
        success "Rollback complete. Snapshot $id removed."
    else
        warn "Rollback finished with errors. Snapshot $id retained."
    fi

    return "$failed"

}
