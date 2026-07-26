#!/usr/bin/env bash

########################################
# Snapshot storage location
########################################

SNAPSHOT_DIR="${HYPRX_SNAPSHOT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hyprx/snapshots}"

########################################
# Save a snapshot of this install run
########################################
#
# Records only packages that were newly
# installed this run (INSTALLED_PACKAGES).
# Already-present packages are never
# touched by rollback.
#

save_snapshot() {

    mkdir -p "$SNAPSHOT_DIR"

    if (( ${#INSTALLED_PACKAGES[@]} == 0 )); then
        return 0
    fi

    local id
    id="$(date +%Y%m%d-%H%M%S)"

    local file="$SNAPSHOT_DIR/$id.snapshot"

    {
        echo "PROFILE=${PROFILE:-unknown}"
        echo "DATE=$(date)"
        echo "PACKAGES=${#INSTALLED_PACKAGES[@]}"
        echo "---"
        printf "%s\n" "${INSTALLED_PACKAGES[@]}"
    } > "$file"

    info "Snapshot saved: $id"

    LAST_SNAPSHOT_ID="$id"

}

########################################
# List available snapshots
########################################

list_snapshots() {

    [[ -d "$SNAPSHOT_DIR" ]] || return 0

    local file id profile date count

    for file in "$SNAPSHOT_DIR"/*.snapshot; do

        [[ -f "$file" ]] || continue

        id="$(basename "$file" .snapshot)"
        profile="$(grep '^PROFILE=' "$file" | cut -d= -f2-)"
        date="$(grep '^DATE=' "$file" | cut -d= -f2-)"
        count="$(grep '^PACKAGES=' "$file" | cut -d= -f2-)"

        printf "%-16s  %-12s  %-4s pkgs  %s\n" "$id" "$profile" "$count" "$date"

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

    sed '1,/^---$/d' "$file"

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

    local pkg
    local failed=0

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

    if (( failed == 0 )); then
        remove_snapshot "$id"
        success "Rollback complete. Snapshot $id removed."
    else
        warn "Rollback finished with errors. Snapshot $id retained."
    fi

    return "$failed"

}
