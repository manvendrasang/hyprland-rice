#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# One fixed log name, overwritten each run - timestamped logs accumulate
# forever and make the run you care about harder to find.
TEST_LOG_DIR="$ROOT_DIR/tests"
TEST_LOG="$TEST_LOG_DIR/test-results.log"
: >"$TEST_LOG"

# Isolate tests from the real repo state
TEST_ROOT="$(mktemp -d)"
cp -r "$ROOT_DIR/config" "$TEST_ROOT/"

export HYPRX_CONFIG="$TEST_ROOT/config"
export HYPRX_TARGET_HOME="$TEST_ROOT/home"

# One master override. lib/state.sh derives every log, report, snapshot and
# backup path from this, so a single assignment isolates the whole suite.
export HYPRX_STATE_DIR="$TEST_ROOT/state"

# Per-path overrides, still honoured by lib/state.sh, for the few tests that
# need a path outside the state dir.
export HYPRX_REPORT_FILE="$TEST_ROOT/state/HyprX-Install-Report.txt"

# Previously these two were hardcoded to the real ~/.local/state/hyprx, so the
# suite used to write to (and read from) the user's actual state dir.
export HYPRX_LOGGER_DIR=""
export HYPRX_RECOVERY_STATE_DIR=""

mkdir -p "$HYPRX_TARGET_HOME/.config"

trap 'rm -rf "$TEST_ROOT"' EXIT

source "$ROOT_DIR/lib/bootstrap.sh"

# Defined up front: the clean-sandbox and CLI sections both invoke it.
CLI="$ROOT_DIR/bin/hyprx"

PASSED=0
FAILED=0

# Log both to stdout and to the log file
log() {
    printf "%s\n" "$*" | tee -a "$TEST_LOG"
}

pass() { log "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { log "  [FAIL] $1"; FAILED=$((FAILED + 1)); }

assert_equals() {
    if [[ "$1" == "$2" ]]; then pass "$2"; else fail "Expected '$1' got '$2'"; fi
}

assert_true() {
    if "$@" >/dev/null 2>&1; then pass "$*"; else fail "$*"; fi
}

# Echo a command's exit code without tripping `set -e`, so one broken probe
# cannot truncate the run (and the log) before the remaining tests execute.
run_capture() {
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    printf '%s' "$rc"
}

# Assert a command exits with one of the codes listed in $2 (comma separated).
# Usage: assert_exit_in "<label>" "<0,1,2>" <cmd> [args...]
assert_exit_in() {
    local label="$1"
    local codes="$2"
    shift 2

    local rc
    rc="$(run_capture "$@")"

    local ok=0
    local a
    local IFS=','
    # shellcheck disable=SC2206  # deliberate word-split of the codes list on IFS
    local -a allowed=($codes)
    unset IFS

    for a in "${allowed[@]}"; do
        [[ "$rc" == "$a" ]] && ok=1
    done

    if (( ok )); then
        pass "$label (exit $rc)"
    else
        fail "$label exited $rc, expected one of: $codes"
    fi
}

assert_false() {
    if "$@" >/dev/null 2>&1; then fail "$*"; else pass "$*"; fi
}

assert_file_exists() {
    if [[ -f "$1" ]]; then pass "$1 exists"; else fail "$1 missing"; fi
}

assert_not_empty() {
    if [[ -n "$1" ]]; then pass "value exists"; else fail "value empty"; fi
}

log "========================================="
log "        HyprX Test Suite"
log "========================================="
log "Started: $(date)"
log "Log file: $TEST_LOG"
log ""

# Test: Bootstrap
log "Testing bootstrap..."
assert_equals true "$HYPRX_INITIALIZED"
assert_true test -d "$HYPRX_CONFIG"
assert_true test -d "$HYPRX_COMMANDS"

# Test: Config
log "Testing config..."
assert_equals default "$(hyprx_config_get THEME)"
hyprx_config_set THEME dark
hyprx_config_load
assert_equals dark "$HYPRX_CONFIG_THEME"
hyprx_config_set THEME default

# Config keys must not leak into the global namespace - a bare
# PACKAGE_MANAGER=auto in hyprx.conf used to collide with the detected value.
hyprx_config_load >/dev/null 2>&1
if [[ -n "${PACKAGE_MANAGER:-}" ]] || [[ -n "${THEME:-}" ]] \
   || [[ -n "${AUTO_CONFIRM:-}" ]] || [[ -n "${LOG_LEVEL:-}" ]]; then
    fail "config leaked unprefixed globals (PACKAGE_MANAGER/THEME/AUTO_CONFIRM/LOG_LEVEL)"
else
    pass "config keys stay namespaced"
fi

# Every declared key must be readable and writable.
for cfg_key in THEME AUTO_CONFIRM ENABLE_GPU_OFFLOAD BACKUP_ON_DEPLOY \
              LOG_LEVEL LOG_FILE PACKAGE_MANAGER; do
    assert_true hyprx_config_get "$cfg_key"
done
assert_false hyprx_config_get NOT_A_REAL_KEY
assert_false hyprx_config_set NOT_A_REAL_KEY value
pass "config keys OK"

# The file must round-trip through save -> load.
hyprx_config_set LOG_LEVEL debug
hyprx_config_load
assert_equals debug "$(hyprx_config_get LOG_LEVEL)"
hyprx_config_set LOG_LEVEL info
hyprx_config_set THEME default

# An unknown key must be reported, not silently executed/accepted.
printf 'HYPRX_CONFIG_THEME=default\nNOT_A_KEY=evil\n' >"$HYPRX_CONFIG_FILE"
unknown_key_out="$(hyprx_config_load 2>&1)"
if printf '%s' "$unknown_key_out" | grep -q "NOT_A_KEY"; then
    pass "unknown config key is reported"
else
    fail "unknown config key silently ignored"
fi
hyprx_config_load >/dev/null 2>&1

# Test: Detection
log "Testing detection..."
# CPU/GPU vendor need lscpu/lspci, which a minimal container may not ship -
# assert they were probed (possibly "unknown") rather than non-empty.
assert_not_empty "$HYPRX_DETECT_DISTRO"
assert_not_empty "$HYPRX_DETECT_PACKAGE_MANAGER"
if hyprx_util_command_exists lscpu; then
    assert_not_empty "$HYPRX_DETECT_CPU_VENDOR"
else
    hyprx_ui_info "lscpu not available - skipping CPU vendor assertion"
fi
if hyprx_util_command_exists lspci; then
    assert_not_empty "$HYPRX_DETECT_GPU_VENDOR"
else
    hyprx_ui_info "lspci not available - skipping GPU vendor assertion"
fi

# Test: Logging
log "Testing logging..."
rm -f "$HYPRX_LOGGER_FILE"
hyprx_ui_info "Info"
hyprx_ui_warn "Warning"
hyprx_ui_error "Error"
hyprx_ui_success "Success"
assert_file_exists "$HYPRX_LOGGER_FILE"
assert_true grep -q INFO "$HYPRX_LOGGER_FILE"
assert_true grep -q WARN "$HYPRX_LOGGER_FILE"
assert_true grep -q ERROR "$HYPRX_LOGGER_FILE"
assert_true grep -q SUCCESS "$HYPRX_LOGGER_FILE"

# Test: Table output
# No progress bar/spinner: those files were removed as dead code.
log "Testing table output..."
hyprx_table_header
hyprx_table_row "Test" "OK"
pass "Table output OK"

# Test: Packages
log "Testing packages..."
# These query a real pacman database. Skip rather than fail where pacman
# isn't present, so the suite is runnable on a non-Arch box (the CI lint job
# used to run on ubuntu-latest and failed here).
if hyprx_util_command_exists pacman; then
    assert_true hyprx_pkg_installed bash
    assert_true hyprx_pkg_exists_official bash
    assert_false hyprx_pkg_installed hyprx-definitely-not-a-real-package
else
    hyprx_ui_info "pacman not available - skipping package database queries"
    pass "package database queries skipped (no pacman)"
fi

# Test: Requirements
log "Testing requirements..."
HINT="$(hyprx_requirements_get_hint steam)"
assert_not_empty "$HINT"
assert_true grep -q "multilib" <<< "$HINT"
UNKNOWN_HINT="$(hyprx_requirements_get_hint totally-not-a-real-package)"
assert_equals "" "$UNKNOWN_HINT"

# Test: Replacements
log "Testing replacements..."
if [[ -f "$HYPRX_DATABASE/package-replacements.conf" ]]; then
    while IFS='=' read -r old new; do
        [[ -z "$old" ]] && continue
        [[ "$old" =~ ^# ]] && continue
        replacement="$(hyprx_replacements_get "$old")"
        [[ "$replacement" == "$new" ]] && pass "$old -> $new" || fail "$old -> $new (got: $replacement)"
    done < "$HYPRX_DATABASE/package-replacements.conf"
fi

# Test: Installer Pipeline
log "Testing installer pipeline..."
[[ "${HYPRX_INITIALIZED:-false}" == "true" ]]
hyprx_resolver_resolve
[[ ${#HYPRX_INSTALL_QUEUE[@]} -gt 0 ]]
UNIQUE_COUNT="$(printf "%s\n" "${HYPRX_INSTALL_QUEUE[@]}" | sort -u | wc -l)"
[[ "$UNIQUE_COUNT" -eq "${#HYPRX_INSTALL_QUEUE[@]}" ]]
pass "Installer pipeline OK"

# Test: Config Deployment
log "Testing config deployment..."
hyprx_snapshot_init_id
TARGET="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr"
rm -rf "$TARGET"
HYPRX_SNAPSHOT_CONFIG_BACKUPS=()
hyprx_deploy_config_dir hypr
assert_true test -d "$TARGET"
assert_true test -f "$TARGET/hyprland.lua"
assert_equals "hypr:false" "${HYPRX_SNAPSHOT_CONFIG_BACKUPS[0]}"
echo "# user edit" >> "$TARGET/hyprland.lua"
HYPRX_SNAPSHOT_CONFIG_BACKUPS=()
hyprx_deploy_config_dir hypr
assert_equals "hypr:true" "${HYPRX_SNAPSHOT_CONFIG_BACKUPS[0]}"
BACKUP_DIR="$(hyprx_snapshot_backup_dir_for "$(hyprx_snapshot_current_id)")/hypr"
assert_true test -d "$BACKUP_DIR"
assert_true grep -q "user edit" "$BACKUP_DIR/hyprland.lua"
assert_false grep -q "user edit" "$TARGET/hyprland.lua"
pass "Config deployment OK"

# Test: Orphaned Target Cleanup
log "Testing orphaned-target cleanup..."
ORPHAN_TARGET="${HYPRX_TARGET_HOME:-$HOME}/.config/orphan-theme"
rm -rf "$ORPHAN_TARGET"
mkdir -p "$ORPHAN_TARGET"
echo "leftover" > "$ORPHAN_TARGET/gtk.css"
hyprx_snapshot_write_deployed hypr orphan-theme
HYPRX_SNAPSHOT_CONFIG_BACKUPS=()
HYPRX_CONFIG_TARGETS="hypr" hyprx_deploy_remove_orphaned
assert_false test -e "$ORPHAN_TARGET"
assert_equals "orphan-theme:true" "${HYPRX_SNAPSHOT_CONFIG_BACKUPS[0]}"
ORPHAN_BACKUP="$(hyprx_snapshot_backup_dir_for "$(hyprx_snapshot_current_id)")/orphan-theme"
assert_true test -f "$ORPHAN_BACKUP/gtk.css"
assert_true grep -q "leftover" "$ORPHAN_BACKUP/gtk.css"
assert_true test -d "$TARGET"
HYPRX_SNAPSHOT_CONFIG_BACKUPS=()
hyprx_snapshot_write_deployed hypr never-deployed
HYPRX_CONFIG_TARGETS="hypr" hyprx_deploy_remove_orphaned
assert_equals "0" "${#HYPRX_SNAPSHOT_CONFIG_BACKUPS[@]}"
pass "Orphaned-target cleanup OK"

# Test: Snapshot/Rollback
log "Testing snapshot/rollback..."
hyprx_snapshot_init_id
hyprx_pkg_remove() { echo "stub-removed: $1"; return 0; }
HYPRX_INSTALL_INSTALLED=(fake-pkg-one fake-pkg-two)
hyprx_snapshot_save
assert_not_empty "$HYPRX_SNAPSHOT_LAST_ID"
SNAPSHOT_ID="$HYPRX_SNAPSHOT_LAST_ID"
assert_true hyprx_snapshot_exists "$SNAPSHOT_ID"
assert_true grep -q "$SNAPSHOT_ID" <(hyprx_snapshot_list)
PACKAGES_OUT="$(hyprx_snapshot_packages "$SNAPSHOT_ID")"
assert_equals "$(printf 'fake-pkg-one\nfake-pkg-two')" "$PACKAGES_OUT"
assert_equals "$SNAPSHOT_ID" "$(hyprx_snapshot_latest)"
hyprx_snapshot_rollback "$SNAPSHOT_ID" >/dev/null
assert_false hyprx_snapshot_exists "$SNAPSHOT_ID"

hyprx_snapshot_init_id
HYPRX_SNAPSHOT_CONFIG_BACKUPS=()
HYPRX_INSTALL_INSTALLED=(fake-pkg-three)
TARGET="${HYPRX_TARGET_HOME:-$HOME}/.config/hypr"
rm -rf "$TARGET"
hyprx_deploy_config_dir hypr
hyprx_snapshot_save
SNAPSHOT_ID="$HYPRX_SNAPSHOT_LAST_ID"
CONFIGS_OUT="$(hyprx_snapshot_configs "$SNAPSHOT_ID")"
assert_equals "hypr:false" "$CONFIGS_OUT"
assert_true test -d "$TARGET"
hyprx_snapshot_rollback "$SNAPSHOT_ID" >/dev/null
assert_false test -d "$TARGET"
assert_false hyprx_snapshot_exists "$SNAPSHOT_ID"
pass "Snapshot/rollback OK"

# Test: Retry
log "Testing retry..."
hyprx_retry 1 true
pass "Retry OK"

# Test: Report Generation
log "Testing report generation..."
HYPRX_INSTALL_FAILED=()
HYPRX_INSTALL_INSTALLED=()
HYPRX_INSTALL_SKIPPED=()
export HYPRX_REPORT_FILE="/tmp/hyprx-test-report.txt"
hyprx_report_generate >/dev/null
assert_file_exists "$HYPRX_REPORT_FILE"
pass "Report generation OK"

# Test: Dry run
log "Testing dry-run semantics..."

# The flag itself
assert_false hyprx_util_dry_run
assert_true env HYPRX_DRY_RUN=1 bash -c "source '$ROOT_DIR/lib/bootstrap.sh' && hyprx_util_dry_run"

DRY_HOME="$TEST_ROOT/dryrun-home"
export HYPRX_TARGET_HOME_SAVED="$HYPRX_TARGET_HOME"
export HYPRX_TARGET_HOME="$DRY_HOME"
mkdir -p "$HYPRX_TARGET_HOME/.config"
export HYPRX_DRY_RUN=1

# Config deploy must report but not copy anything.
hyprx_deploy_config_dir hypr
assert_false test -d "$HYPRX_TARGET_HOME/.config/hypr"

# A package that cannot possibly exist: even if the dry-run guard were
# dropped, pacman could not install it, so this assertion is safe.
hyprx_pkg_install_official hyprx-nonexistent-pkg-xyz >/dev/null 2>&1
assert_equals 0 "$?"
assert_false hyprx_pkg_installed hyprx-nonexistent-pkg-xyz

# No snapshot, no recovery state, no deploy-target ledger.
hyprx_snapshot_init_id
HYPRX_INSTALL_INSTALLED=(hyprx-fake-pkg)
hyprx_snapshot_save
assert_false hyprx_snapshot_exists "$(hyprx_snapshot_current_id)"

HYPRX_INSTALL_QUEUE=(hyprx-fake-a hyprx-fake-b)
hyprx_recovery_save_state
assert_false hyprx_recovery_has_state
hyprx_recovery_clear_state

# The report must be stamped so nobody mistakes it for a real install.
hyprx_report_generate >/dev/null
if grep -q "DRY RUN" "$HYPRX_REPORT_FILE"; then
    pass "dry-run report is stamped"
else
    fail "dry-run report missing its DRY RUN banner"
fi

export HYPRX_DRY_RUN=0
export HYPRX_TARGET_HOME="$HYPRX_TARGET_HOME_SAVED"

# And the guard must be fully released: a normal deploy now really copies.
hyprx_deploy_config_dir hypr
assert_true test -f "$HYPRX_TARGET_HOME/.config/hypr/hyprland.lua"
rm -rf "$HYPRX_TARGET_HOME/.config/hypr"

# Every configured target must actually be deployable. "gtk-3.0" was being
# rejected by an over-strict name check and silently never deployed, so this
# asserts the whole target list is accepted, not just the sample above.
for target_dir in $HYPRX_CONFIG_TARGETS; do
    if ! hyprx_deploy_config_dir "$target_dir" >/dev/null 2>&1; then
        fail "deploy target rejected: $target_dir"
    fi
    if [[ ! -d "$HYPRX_TARGET_HOME/.config/$target_dir" ]]; then
        fail "deploy target missing after deploy: $target_dir"
    fi
done
pass "all deploy targets accepted (incl. gtk-3.0)"

# Traversal attempts must still be rejected.
for bad_name in "../escape" "a/b" "." ".."; do
    if hyprx_deploy_config_dir "$bad_name" >/dev/null 2>&1; then
        fail "path traversal accepted: $bad_name"
    else
        pass "path traversal rejected: $bad_name"
    fi
done

rm -rf "${HYPRX_TARGET_HOME:?}/.config"
pass "Dry-run semantics OK"

# Test: Clean sandbox
# HYPRX_CLEAN_ROOT runs the real deletion logic against a throwaway tree;
# without it only --dry-run is testable and the rm/find calls go unexercised.
log "Testing clean sandbox..."
CLEAN_SANDBOX_ROOT="$TEST_ROOT/clean-sandbox"
mkdir -p "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots"
mkdir -p "$CLEAN_SANDBOX_ROOT/.cache/thumbnails/normal/large"
mkdir -p "$CLEAN_SANDBOX_ROOT/.cache/mesa_shader_cache"

touch "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/old.png"
touch -d '3 days ago' "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/old.png"
touch "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/fresh.png"
echo "cached" >"$CLEAN_SANDBOX_ROOT/.cache/thumbnails/normal/large/xyz"
echo "cached" >"$CLEAN_SANDBOX_ROOT/.cache/mesa_shader_cache/blob"

assert_exit_in "hyprx clean (sandbox)" "0" env HYPRX_CLEAN_ROOT="$CLEAN_SANDBOX_ROOT" "$CLI" clean

assert_false test -e "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/old.png"
assert_true  test -e "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/fresh.png"
# Cache directories themselves must survive; only their contents go.
assert_true  test -d "$CLEAN_SANDBOX_ROOT/.cache/thumbnails"
assert_false test -e "$CLEAN_SANDBOX_ROOT/.cache/thumbnails/normal/large/xyz"
assert_false test -e "$CLEAN_SANDBOX_ROOT/.cache/mesa_shader_cache/blob"

# And --dry-run against the same tree must change nothing.
touch -d '3 days ago' "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/fresh.png"
assert_exit_in "hyprx clean (sandbox --dry-run)" "0" env HYPRX_CLEAN_ROOT="$CLEAN_SANDBOX_ROOT" "$CLI" clean --dry-run
assert_true test -e "$CLEAN_SANDBOX_ROOT/Pictures/Screenshots/fresh.png"
pass "Clean sandbox OK"

# Test: Wallpaper startup path
# A blank-desktop-on-login bug had two independent causes, neither checked:
# hyprpaper's conf pinned a non-existent absolute path, and waypaper can exit
# 0 having set nothing.
log "Testing wallpaper startup path..."

WPSCRIPT="$ROOT_DIR/scripts/wallpaper-restore.sh"
assert_true test -x "$WPSCRIPT"
assert_true bash -n "$WPSCRIPT"

# The repo template must not carry a wallpaper block: a machine-specific path
# is what hyprpaper failed to resolve, logging "no wp will be created".
if [[ -f "$ROOT_DIR/config/hypr/hyprpaper.conf" ]]; then
    if grep -qE '^[[:space:]]*path[[:space:]]*=' "$ROOT_DIR/config/hypr/hyprpaper.conf"; then
        fail "config/hypr/hyprpaper.conf ships a wallpaper path (must stay runtime-owned)"
    else
        pass "hyprpaper.conf template carries no wallpaper path"
    fi
else
    fail "config/hypr/hyprpaper.conf missing"
fi

# Every path the template or scripts reference must at least not be an
# absolute path under a now-nonexistent home-relative guess.
if grep -rn "/home/[a-z]*/wallpaper/" "$ROOT_DIR/config" 2>/dev/null | grep -q .; then
    fail "a ~/wallpaper/ absolute path is still baked into config/"
else
    pass "no stale ~/wallpaper/ path in config"
fi

# The restore script must verify its own result rather than trusting exit 0.
for required in "listactive" "wait_for_hyprpaper" "sync_conf" "apply_direct"; do
    if grep -q "$required" "$WPSCRIPT"; then
        pass "restore script has $required"
    else
        fail "restore script missing $required (no verification?)"
    fi
done

# Deploying the hypr config must not clobber a live hyprpaper.conf.
WPCONF_HOME="$TEST_ROOT/wp-home"
mkdir -p "$WPCONF_HOME/.config"
printf 'wallpaper {\n    monitor =\n    path = /some/real/wallpaper.jpg\n    fit_mode = cover\n}\nipc = true\n' \
    >"$WPCONF_HOME/.config/hyprpaper.conf"
mkdir -p "$WPCONF_HOME/.config/hypr"
cp "$WPCONF_HOME/.config/hyprpaper.conf" "$WPCONF_HOME/.config/hypr/hyprpaper.conf"

export HYPRX_TARGET_HOME_SAVED="$HYPRX_TARGET_HOME"
export HYPRX_TARGET_HOME="$WPCONF_HOME"
hyprx_snapshot_init_id
hyprx_deploy_config_dir hypr >/dev/null 2>&1
if grep -q "/some/real/wallpaper.jpg" "$WPCONF_HOME/.config/hypr/hyprpaper.conf" 2>/dev/null; then
    pass "deploy preserved the live hyprpaper.conf"
else
    fail "deploy clobbered the live hyprpaper.conf"
fi
if ls -A "$WPCONF_HOME/.config/" 2>/dev/null | grep -q "preserved"; then
    fail "deploy left a temp file behind in .config/"
else
    pass "deploy left no temp files behind"
fi
export HYPRX_TARGET_HOME="$HYPRX_TARGET_HOME_SAVED"
pass "Wallpaper startup path OK"

# Test: Waybar startup path
# Same class as the wallpaper bug: the old ensure-waybar.sh treated "a waybar
# process exists" as success, but waybar can run with no layer-shell surface -
# so it exited 0, nothing retried, and the bar was gone all session.
log "Testing waybar startup path..."

ENSURE_WAYBAR="$ROOT_DIR/config/waybar/scripts/ensure-waybar.sh"
assert_true test -x "$ENSURE_WAYBAR"
assert_true bash -n "$ENSURE_WAYBAR"

# It must verify the compositor registered the surface, not just the process.
if grep -q "namespace: waybar" "$ENSURE_WAYBAR"; then
    pass "ensure-waybar checks for a registered layer surface"
else
    fail "ensure-waybar does not check for a layer surface (pgrep-only check)"
fi

# It must be able to clear a stuck waybar that would otherwise satisfy a
# process-only check and block every retry.
if grep -q "waybar_is_stuck" "$ENSURE_WAYBAR"; then
    pass "ensure-waybar clears a surface-less waybar before retrying"
else
    fail "ensure-waybar cannot recover from a stuck waybar"
fi

# Failures must be logged, not silent.
if grep -q "FAILED" "$ENSURE_WAYBAR" && grep -q "hyprx.log\|LOG_FILE" "$ENSURE_WAYBAR"; then
    pass "ensure-waybar logs its failure"
else
    fail "ensure-waybar fails silently"
fi

# The reload must not be a blind kill-and-forget (`pkill` + unverified
# restart) - the wallust daemon fires exactly that in the first seconds of a
# session, when the display may not be ready yet.
RELOAD_WAYBAR="$ROOT_DIR/scripts/reload-waybar.sh"
if grep -q "ensure-waybar.sh" "$RELOAD_WAYBAR" && grep -q -- "--restart" "$RELOAD_WAYBAR"; then
    pass "reload-waybar delegates to the verified startup path"
else
    fail "reload-waybar is still a blind pkill + fire-and-forget restart"
fi

# It must not hand-roll its own pkill/nohup restart.
if grep -qE '^\s*(nohup waybar|waybar &)' "$RELOAD_WAYBAR"; then
    fail "reload-waybar still starts waybar directly instead of delegating"
else
    pass "reload-waybar has a single start path"
fi

# --restart must exist and be documented in the startup helper.
if grep -q -- "--restart" "$ENSURE_WAYBAR"; then
    pass "ensure-waybar supports --restart"
else
    fail "ensure-waybar has no --restart mode"
fi

# A restart must wait for the old surface to disappear, or the health check
# can see the outgoing waybar's layer and wrongly call it healthy.
if grep -q "restart_wait" "$ENSURE_WAYBAR"; then
    pass "ensure-waybar --restart waits for the old surface to clear"
else
    fail "ensure-waybar --restart does not wait for the old surface"
fi

# hyprland.lua autostarts the deployed copy; both must exist and be runnable.
assert_file_exists "$ROOT_DIR/config/waybar/scripts/ensure-waybar.sh"
if grep -q "ensure-waybar.sh" "$ROOT_DIR/config/hypr/hyprland.lua"; then
    pass "hyprland.lua autostarts ensure-waybar.sh"
else
    fail "hyprland.lua does not autostart ensure-waybar.sh"
fi

# Every script hyprland.lua autostarts must actually exist in the repo, or the
# exec_cmd silently does nothing. This is the failure that produced a missing
# bar with no error at all.
while IFS= read -r ref; do
    # Skip brace-expansion shorthand in comments, e.g. "{music,bluetooth}-daemon.sh".
    [[ "$ref" == *"{"* ]] && continue

    # Map each autostarted path back to where it lives in the repo.
    case "$ref" in
        */.config/waybar/scripts/*) repo_path="$ROOT_DIR/config/waybar/scripts/${ref##*/}" ;;
        */.local/share/hyprx/scripts/*) repo_path="$ROOT_DIR/scripts/${ref##*/}" ;;
        *) repo_path="$ROOT_DIR/${ref#\~/}" ;;
    esac

    if [[ -x "$repo_path" ]]; then
        pass "autostart target exists: ${ref##*/}"
    else
        fail "autostart target missing: $ref (expected $repo_path)"
    fi
done < <(grep -oE '(~/\.config/waybar/scripts/|~/\.local/share/hyprx/scripts/)[A-Za-z0-9._-]+\.sh' \
         "$ROOT_DIR/config/hypr/hyprland.lua" | sort -u)
pass "Waybar startup path OK"

# Synced at login only, the conf drifts on the first wallpaper change and the
# next hyprpaper restart reverts it - waypaper never writes the conf.
SYNC_CONF="$ROOT_DIR/scripts/sync-hyprpaper-conf.sh"
assert_true test -x "$SYNC_CONF"
assert_true bash -n "$SYNC_CONF"

# Both sides of a wallpaper change must call it.
if grep -q "sync-hyprpaper-conf.sh" "$ROOT_DIR/scripts/apply-wallust-theme.sh"; then
    pass "apply-wallust-theme syncs hyprpaper.conf on every change"
else
    fail "apply-wallust-theme does not sync hyprpaper.conf (only login is protected)"
fi
if grep -q "sync-hyprpaper-conf.sh" "$ROOT_DIR/scripts/wallpaper-restore.sh"; then
    pass "wallpaper-restore syncs hyprpaper.conf at login"
else
    fail "wallpaper-restore does not sync hyprpaper.conf"
fi

# Exercise the sync helper against a sandboxed conf.
SYNC_TEST_HOME="$TEST_ROOT/sync-home"
mkdir -p "$SYNC_TEST_HOME/.config/hypr"
SYNC_IMG="$ROOT_DIR/config/hypr/hyprlock.conf"   # any real file
env HYPRX_TARGET_HOME="$SYNC_TEST_HOME" "$SYNC_CONF" "$SYNC_IMG"
if grep -qF "path = $SYNC_IMG" "$SYNC_TEST_HOME/.config/hypr/hyprpaper.conf" 2>/dev/null; then
    pass "sync-hyprpaper-conf writes the given path"
else
    fail "sync-hyprpaper-conf did not write the path"
fi

# Idempotent: same path again must not rewrite the file.
SYNC_BEFORE="$(stat -c %Y "$SYNC_TEST_HOME/.config/hypr/hyprpaper.conf")"
sleep 1
env HYPRX_TARGET_HOME="$SYNC_TEST_HOME" "$SYNC_CONF" "$SYNC_IMG"
SYNC_AFTER="$(stat -c %Y "$SYNC_TEST_HOME/.config/hypr/hyprpaper.conf")"
assert_equals "$SYNC_BEFORE" "$SYNC_AFTER"

# A path that does not exist must be refused, not written into the conf -
# that is precisely the state that produced "no wp will be created".
env HYPRX_TARGET_HOME="$SYNC_TEST_HOME" "$SYNC_CONF" "/nonexistent/nope.jpg"
if grep -qF "/nonexistent/nope.jpg" "$SYNC_TEST_HOME/.config/hypr/hyprpaper.conf" 2>/dev/null; then
    fail "sync-hyprpaper-conf wrote a non-existent path"
else
    pass "sync-hyprpaper-conf refuses a non-existent path"
fi
pass "hyprpaper.conf sync OK"

# Test: Install/Uninstall
log "Testing install/uninstall..."
INSTALL_TEST_ROOT="$(mktemp -d)"
export HYPRX_INSTALL_DIR="$INSTALL_TEST_ROOT/share/hyprx"
export HYPRX_BIN_DIR="$INSTALL_TEST_ROOT/bin"
bash "$ROOT_DIR/install.sh" >/dev/null
assert_true test -d "$HYPRX_INSTALL_DIR"
assert_true test -f "$HYPRX_INSTALL_DIR/bin/hyprx"
assert_true test -L "$HYPRX_BIN_DIR/hyprx"
assert_true test -L "$HYPRX_BIN_DIR/prime-run"
assert_true test -L "$HYPRX_BIN_DIR/hyprx-settings"
assert_false test -d "$HYPRX_INSTALL_DIR/.git"
"$HYPRX_BIN_DIR/hyprx" help >/dev/null
bash "$ROOT_DIR/install.sh" >/dev/null
assert_true test -f "$HYPRX_INSTALL_DIR/bin/hyprx"
bash "$ROOT_DIR/uninstall.sh" >/dev/null
assert_false test -d "$HYPRX_INSTALL_DIR"
assert_false test -e "$HYPRX_BIN_DIR/hyprx"
assert_false test -e "$HYPRX_BIN_DIR/prime-run"
# uninstall.sh used to leave this one behind, dangling into the removed dir.
assert_false test -e "$HYPRX_BIN_DIR/hyprx-settings"
rm -rf "$INSTALL_TEST_ROOT"
pass "Install/uninstall OK"

# Test: CLI
log "Testing CLI..."

# Read-only / non-destructive probes only. `hyprx clean` (no flags) really
# does vacuum the journal, wipe the pacman cache, clear thumbnail caches
# and rm files out of /tmp - never invoke that from a test run.
assert_exit_in "hyprx (no args)"            "0"      "$CLI"
assert_exit_in "hyprx help"                 "0"      "$CLI" help
assert_exit_in "hyprx doctor"               "0,1,2"  "$CLI" doctor

# Tolerating doctor's exit 2 (as the smoke check above must) would let a commit
# that breaks hyprland.lua, a .jsonc or hyprlock.conf ship green - so those
# checks are re-run here directly against the repo's own files.

LUA_CHECKER=""
for candidate in luac luac5.4 luac5.3 luac5.1; do
    if hyprx_util_command_exists "$candidate"; then
        LUA_CHECKER="$candidate"
        break
    fi
done

if [[ -n "$LUA_CHECKER" ]]; then
    while IFS= read -r -d '' lua_file; do
        if ! "$LUA_CHECKER" -p "$lua_file" >/dev/null 2>&1; then
            fail "Lua syntax error: ${lua_file#"$ROOT_DIR"/}"
        else
            pass "valid Lua: ${lua_file#"$ROOT_DIR"/}"
        fi
    done < <(find "$ROOT_DIR/config" -name '*.lua' -type f -print0)
else
    hyprx_ui_info "no Lua checker available - skipping .lua validation"
fi

# JSON/JSONC: parse every deployed config file. A broken one crash-loops
# whatever reads it.
JSON_VALIDATOR=""
if hyprx_util_command_exists jq; then
    JSON_VALIDATOR="jq"
elif hyprx_util_command_exists python3; then
    JSON_VALIDATOR="python3"
fi

if [[ -z "$JSON_VALIDATOR" ]]; then
    hyprx_ui_info "no JSON validator (jq or python3) - skipping .json/.jsonc validation"
else
    while IFS= read -r -d '' json_file; do
        [[ -s "$json_file" ]] || continue    # empty stub, nothing reads it
        json_rc=0
        case "$JSON_VALIDATOR" in
            jq) sed 's#//.*##' "$json_file" | jq empty >/dev/null 2>&1 || json_rc=$? ;;
            python3) python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
json.loads(re.sub(r"//.*", "", text))
' "$json_file" >/dev/null 2>&1 || json_rc=$? ;;
        esac
        if (( json_rc == 0 )); then
            pass "valid JSON: ${json_file#"$ROOT_DIR"/}"
        else
            fail "invalid JSON: ${json_file#"$ROOT_DIR"/}"
        fi
    done < <(find "$ROOT_DIR/config" \( -name '*.json' -o -name '*.jsonc' \) -type f -print0)
fi

# hyprlock.conf: brace balance. An imbalance makes hyprlock fail to start or
# silently misparse a block.
HYPRLOCK="$ROOT_DIR/config/hypr/hyprlock.conf"
if [[ -f "$HYPRLOCK" ]]; then
    open_braces=$(grep -o '{' "$HYPRLOCK" | wc -l)
    close_braces=$(grep -o '}' "$HYPRLOCK" | wc -l)
    if [[ "$open_braces" == "$close_braces" ]]; then
        pass "hyprlock.conf braces balanced ($open_braces pairs)"
    else
        fail "hyprlock.conf braces unbalanced ($open_braces open, $close_braces close)"
    fi
else
    fail "config/hypr/hyprlock.conf missing"
fi
assert_exit_in "hyprx clean --dry-run"      "0"      "$CLI" clean --dry-run
assert_exit_in "hyprx rollback list"        "0"      "$CLI" rollback list
assert_exit_in "hyprx rollback help"        "0"      "$CLI" rollback help

# Unknown subcommand must fail cleanly with a usage hint, not crash with
# "command not found" from an unrenamed helper.
unknown_out="$("$CLI" definitely-not-a-command 2>&1 || true)"
assert_exit_in "hyprx <unknown>"            "1"      "$CLI" definitely-not-a-command
if printf '%s' "$unknown_out" | grep -q "command not found"; then
    fail "hyprx <unknown> crashed with a shell 'command not found' (stale helper name?)"
else
    pass "hyprx <unknown> reports a clean error"
fi

# Snapshot-id validation must reject malformed ids before touching anything.
assert_exit_in "hyprx rollback <bad-id>"    "1"      "$CLI" rollback "not-a-valid-id"
assert_exit_in "hyprx install --help"       "0"      "$CLI" install --help
assert_exit_in "hyprx install --bogus"      "1"      "$CLI" install --bogus

# Regression guard: `hyprx update` used to ignore arguments, so
# `hyprx update --help` ran a real system-wide upgrade.
assert_exit_in "hyprx update --help"        "0"      "$CLI" update --help
assert_exit_in "hyprx update --bogus"       "1"      "$CLI" update --bogus
assert_exit_in "hyprx update -x"            "1"      "$CLI" update -x

# No command may reach a mutating path via a stray argument. Grepped rather
# than executed. Wording differs per command, so any rejection message counts;
# `help` and `doctor` are exempt (harmless and read-only respectively).
for cmd_file in "$ROOT_DIR"/commands/*.sh; do
    cmd_name="$(basename "$cmd_file" .sh)"
    [[ "$cmd_name" == "help" || "$cmd_name" == "doctor" ]] && continue
    if ! grep -qE 'Unknown option|Unknown action|Invalid snapshot ID|Unknown snapshot' "$cmd_file" 2>/dev/null; then
        fail "commands/$cmd_name.sh does not validate its arguments"
    else
        pass "commands/$cmd_name.sh validates its arguments"
    fi
done
pass "command argument validation present"
assert_exit_in "hyprx clean --help"          "0"      "$CLI" clean --help
assert_exit_in "hyprx clean --bogus"        "1"      "$CLI" clean --bogus

# The config command must reject bad values rather than persisting them.
assert_exit_in "hyprx config --help"        "0"      "$CLI" config --help
assert_exit_in "hyprx config list"          "0"      "$CLI" config list
assert_exit_in "hyprx config get"           "0"      "$CLI" config get THEME
assert_exit_in "hyprx config get <bad>"     "1"      "$CLI" config get NOT_A_KEY
assert_exit_in "hyprx config set <bad key>" "1"      "$CLI" config set NOT_A_KEY value
assert_exit_in "hyprx config set <bad val>" "1"      "$CLI" config set LOG_LEVEL verbose
assert_exit_in "hyprx config set <bad pm>"  "1"      "$CLI" config set PACKAGE_MANAGER apt
assert_exit_in "hyprx config unset <bad>"   "1"      "$CLI" config unset NOT_A_KEY
assert_exit_in "hyprx config bogus action"  "1"      "$CLI" config frobnicate

# A rejected value must not persist.
assert_equals info "$(hyprx_config_get LOG_LEVEL)"
assert_equals auto "$(hyprx_config_get PACKAGE_MANAGER)"

# set/unset round-trip.
hyprx_config_set LOG_LEVEL debug
assert_equals debug "$(hyprx_config_get LOG_LEVEL)"
hyprx_config_unset LOG_LEVEL
assert_equals info "$(hyprx_config_get LOG_LEVEL)"

# Every advertised key must be listable and have a default.
for cfg_key in THEME AUTO_CONFIRM BACKUP_ON_DEPLOY ENABLE_GPU_OFFLOAD \
              LOG_LEVEL LOG_FILE PACKAGE_MANAGER; do
    assert_true hyprx_config_get "$cfg_key"
    assert_true hyprx_config_default_value "$cfg_key"
done
pass "Config command OK"

pass "CLI OK"

# Test: Permissions
log "Checking permissions..."
find "$ROOT_DIR/bin" "$ROOT_DIR/scripts" -type f | while IFS= read -r file; do
    [[ -x "$file" ]] || fail "$file is not executable"
done
pass "Permissions OK"

# Test: Scripts
log "Checking helper scripts..."
for script in backup-config.sh dev-sync.sh reload-hypr.sh reload-waybar.sh; do
    [[ -x "$ROOT_DIR/scripts/$script" ]] && pass "$script executable" || fail "$script not executable"
done
pass "Scripts OK"

# Test: ShellCheck
log "Running ShellCheck..."
SC_FAILED=0
while IFS= read -r -d '' file; do
    if ! shellcheck -x -e SC1090,SC1091,SC2010,SC2015,SC2034,SC2086 "$file" >/dev/null 2>&1; then
        fail "ShellCheck: $file"
        SC_FAILED=1
    fi
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -path "$ROOT_DIR/build" -prune -o -path "$ROOT_DIR/.cache" -prune -o -name "*.sh" -print0)
[[ $SC_FAILED -eq 0 ]] && pass "ShellCheck OK"

# Test: Syntax
log "Checking syntax..."
SYN_FAILED=0
while IFS= read -r -d '' file; do
    if ! bash -n "$file" 2>/dev/null; then
        fail "Syntax: $file"
        SYN_FAILED=1
    fi
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -path "$ROOT_DIR/build" -prune -o -path "$ROOT_DIR/.cache" -prune -o -name "*.sh" -print0)
[[ $SYN_FAILED -eq 0 ]] && pass "Syntax OK"

# Test: Source
log "Testing source..."
for _ in $(seq 25); do
    bash -c "source \"$ROOT_DIR/lib/bootstrap.sh\"" >/dev/null 2>&1 || fail "Bootstrap source failed"
done
pass "Bootstrap sourcing OK"

# Test: Smoke
log "Running smoke test..."
hyprx_resolver_resolve
[[ ${#HYPRX_INSTALL_QUEUE[@]} -gt 0 ]]
assert_file_exists "$ROOT_DIR/services.list"
pass "Smoke test OK"

# Test: Coverage
log "Checking library coverage..."
missing=0
while IFS= read -r file; do
    name="$(basename "$file")"

    # bootstrap.sh is the entry point - it is the thing that sources
    # everything else, so it cannot (and should not) list itself.
    [[ "$name" == "bootstrap.sh" ]] && continue

    # Match the bare filename anywhere in bootstrap.sh, not a `source`
    # line - the source lists use a loop variable.
    if ! grep -qF "$name" "$ROOT_DIR/lib/bootstrap.sh" 2>/dev/null; then
        fail "UNCOVERED: $name (not listed in lib/bootstrap.sh)"
        missing=$((missing + 1))
    fi
done < <(find "$ROOT_DIR/lib" -name '*.sh' -type f | sort)
[[ $missing -eq 0 ]] && pass "Coverage OK"

# ============================================
# State path resolution
# ============================================
log "Testing state path resolution..."

# state.sh must be sourced before logger.sh, which reads the paths it defines.
first_lib="$(sed -n '/^for file in \\/,/do$/p' "$ROOT_DIR/lib/bootstrap.sh" | sed -n '2,$p' | head -1)"
first_lib="${first_lib// /}"
first_lib="${first_lib%\\}"
assert_equals "$first_lib" "state.sh"

# Every path must resolve inside the state dir, not the user's real one.
for var in HYPRX_STATE_LOG_FILE HYPRX_STATE_REPORT_DIR HYPRX_STATE_SNAPSHOT_DIR \
           HYPRX_STATE_BACKUP_DIR HYPRX_STATE_DEPLOYED_FILE HYPRX_STATE_FAILURE_LOG; do
    val="${!var}"
    if [[ "$val" == "$TEST_ROOT/state"* ]]; then
        pass "$var resolves inside the sandbox"
    else
        fail "$var escapes the sandbox: $val"
    fi
done

# doctor.sh used to hardcode the reports path, which ignored XDG_STATE_HOME
# and the override above.
if grep -qF "\$HOME/.local/state/hyprx/reports" "$ROOT_DIR/commands/doctor.sh"; then
    fail "doctor.sh still hardcodes the reports path"
else
    pass "doctor.sh uses the resolved reports path"
fi

# Size and formatting helpers.
mkdir -p "$TEST_ROOT/sizedir"
dd if=/dev/zero of="$TEST_ROOT/sizedir/blob" bs=1024 count=64 2>/dev/null
SZ="$(hyprx_state_size "$TEST_ROOT/sizedir")"
if [[ "$SZ" -gt 60000 && "$SZ" -lt 70000 ]]; then
    pass "hyprx_state_size returns bytes ($SZ)"
else
    fail "hyprx_state_size returned $SZ, expected ~65536"
fi
assert_equals "$(hyprx_state_human 0)"        "0B"
assert_equals "$(hyprx_state_human 2048)"     "2.0K"
assert_equals "$(hyprx_state_human 3145728)"  "3.0M"
assert_equals "$(hyprx_state_human 3221225472)" "3.0G"
assert_equals "$(hyprx_state_size /nonexistent/path)" ""
pass "hyprx_state_size on a missing path is empty"

# ============================================
# Log rotation
# ============================================
log "Testing log rotation..."

ROT="$TEST_ROOT/rot"
rm -rf "$ROT"; mkdir -p "$ROT"
OLD_FILE="$HYPRX_LOGGER_FILE"
OLD_MAX="$HYPRX_LOG_MAX_BYTES"
# Point the logger at the scratch dir and shrink the threshold so a rotation
# happens within a few hundred lines rather than 2 MiB of them.
HYPRX_LOGGER_FILE="$ROT/hyprx.log"
export HYPRX_LOG_MAX_BYTES=2048 HYPRX_LOG_KEEP=2

hyprx_logger_log INFO "first message"
if [[ -f "$ROT/hyprx.log" ]]; then pass "log file created"; else fail "no log file"; fi

# Push past the threshold and confirm it rolls over rather than growing.
for i in $(seq 1 200); do
    hyprx_logger_log INFO "padding message number $i with enough text to exceed the limit"
done
if [[ -f "$ROT/hyprx.log.1" ]]; then
    pass "log rotated to .1"
else
    fail "log never rotated"
fi
SIZE_NOW="$(hyprx_state_size "$ROT/hyprx.log")"
if [[ "$SIZE_NOW" -lt 2048 ]]; then
    pass "active log stays under the threshold ($SIZE_NOW)"
else
    fail "active log grew to $SIZE_NOW past the 2048 threshold"
fi

# Keep-count must be respected: no generation above .2.
for i in $(seq 1 600); do
    hyprx_logger_log INFO "more padding to force several rotations $i"
done
if [[ -f "$ROT/hyprx.log.3" ]]; then
    fail "rotation kept more than the 2 requested generations"
else
    pass "rotation respects HYPRX_LOG_KEEP"
fi

unset HYPRX_LOG_MAX_BYTES HYPRX_LOG_KEEP
export HYPRX_LOG_MAX_BYTES="$OLD_MAX"
HYPRX_LOGGER_FILE="$OLD_FILE"

# ============================================
# clean: new flags and reporting
# ============================================
log "Testing hyprx clean flags..."

SB="$TEST_ROOT/cleanbox"
mkdir -p "$SB/.cache/mesa_shader_cache" "$SB/.cache/yay/pkg" "$SB/Pictures/Screenshots"
dd if=/dev/zero of="$SB/.cache/mesa_shader_cache/blob" bs=1024 count=64 2>/dev/null
dd if=/dev/zero of="$SB/.cache/yay/pkg/blob" bs=1024 count=64 2>/dev/null
touch -d '30 days ago' "$SB/Pictures/Screenshots/old.png"
touch "$SB/Pictures/Screenshots/fresh.png"

assert_exit_in "clean --dry-run" "0" "$CLI" clean --dry-run
assert_exit_in "clean --help"    "0" "$CLI" clean --help
assert_exit_in "clean rejects an unknown flag" "1" "$CLI" clean --bogus

# --dry-run must not remove anything.
if [[ -f "$SB/.cache/mesa_shader_cache/blob" ]]; then
    pass "dry-run leaves caches in place"
else
    fail "dry-run deleted cache contents"
fi
if [[ -f "$SB/Pictures/Screenshots/old.png" ]]; then
    pass "dry-run leaves old screenshots in place"
else
    fail "dry-run deleted an old screenshot"
fi

# --deep must be opt-in: without it the large caches are left alone.
# Checked before any real run, while the fixtures are still in place.
out="$(HYPRX_CLEAN_ROOT="$SB" "$CLI" clean --dry-run 2>&1)"
if printf '%s' "$out" | grep -q 'cache/yay'; then
    fail "--deep steps ran without --deep"
else
    pass "--deep steps are gated behind --deep"
fi

out="$(HYPRX_CLEAN_ROOT="$SB" "$CLI" clean --deep --dry-run 2>&1)"
if printf '%s' "$out" | grep -q 'cache/yay'; then
    pass "--deep includes the large caches"
else
    fail "--deep did not include the large caches"
fi

# A real sandboxed run must reclaim the bytes and report them. HYPRX_CLEAN_ROOT
# aims the home-relative steps at the sandbox; a sandboxed run does remove its
# own targets, so it must not claim otherwise.
out="$(HYPRX_CLEAN_ROOT="$SB" "$CLI" clean --yes 2>&1 || true)"
if printf '%s' "$out" | grep -q 'Sandboxed cleanup removed'; then
    pass "clean reports sandbox mode"
else
    fail "clean did not report sandbox mode"
fi
if printf '%s' "$out" | grep -q 'System-wide steps were reported'; then
    pass "clean says system-wide steps were skipped"
else
    fail "clean did not flag the skipped system-wide steps"
fi
if printf '%s' "$out" | grep -q 'Nothing was removed'; then
    fail "sandboxed run claimed nothing was removed"
else
    pass "sandboxed run does not claim it removed nothing"
fi
if [[ ! -f "$SB/.cache/mesa_shader_cache/blob" ]]; then
    pass "sandboxed clean removed the cache contents"
else
    fail "sandboxed clean left the cache contents"
fi
if [[ ! -f "$SB/Pictures/Screenshots/old.png" ]]; then
    pass "sandboxed clean removed the aged screenshot"
else
    fail "sandboxed clean left the aged screenshot"
fi
if [[ -f "$SB/Pictures/Screenshots/fresh.png" ]]; then
    pass "sandboxed clean kept the fresh screenshot"
else
    fail "sandboxed clean deleted a fresh screenshot"
fi
if printf '%s' "$out" | grep -qE 'removed [0-9]'; then
    pass "clean reports the bytes it reclaimed"
else
    fail "clean did not report reclaimed bytes"
fi
# A second pass has nothing left, and must say exactly that rather than
# claiming a saving.
out2="$(HYPRX_CLEAN_ROOT="$SB" "$CLI" clean --yes 2>&1 || true)"
if printf '%s' "$out2" | grep -q 'removed nothing'; then
    pass "clean says so when nothing needed removing"
else
    fail "clean did not report a zero-byte run"
fi
# The pacman cache size is an upper bound, not a measured saving, so it must
# never inflate the total.
if printf '%s' "$out" | grep -qE 'could free up to [0-9]'; then
    pass "package cache is reported as an upper bound"
else
    fail "package cache estimate not reported as a bound"
fi

# Retention knobs are honoured.
mkdir -p "$TEST_ROOT/state/snapshots"
for i in 1 2 3 4 5 6 7; do
    printf 'x\n' >"$TEST_ROOT/state/snapshots/snap$i.snapshot"
done
HYPRX_CLEAN_ROOT="$SB" SNAPSHOT_KEEP=3 "$CLI" clean >/dev/null 2>&1 || true
n="$(find "$TEST_ROOT/state/snapshots" -name '*.snapshot' | wc -l | tr -d ' ')"
assert_equals "$n" "3"

# Retention defaults are documented in the usage text.
usage="$("$CLI" clean --help 2>&1)"
for knob in SCREENSHOT_AGE_DAYS TMP_AGE_DAYS JOURNAL_RETENTION_DAYS SNAPSHOT_KEEP REPORT_KEEP LOG_KEEP HYPRX_CLEAN_ROOT; do
    if printf '%s' "$usage" | grep -qF "$knob"; then
        pass "clean --help documents $knob"
    else
        fail "clean --help omits $knob"
    fi
done

# ============================================
# doctor: new flags
# ============================================
log "Testing hyprx doctor flags..."

# The JSON shape checks need an interpreter. Arch's `python` package ships
# `python3`, but not every CI image does, so accept either name rather than
# silently skipping the check wherever only one of them exists.
PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done

assert_exit_in "doctor --help" "0" "$CLI" doctor --help
assert_exit_in "doctor rejects an unknown flag" "1" "$CLI" doctor --bogus
assert_exit_in "doctor --no-report" "0,1,2" "$CLI" doctor --no-report
assert_exit_in "doctor --skip storage" "0,1,2" "$CLI" doctor --skip storage --no-report
assert_exit_in "doctor --only storage" "0,1,2" "$CLI" doctor --only storage --no-report

# --json plus --only would emit a document that looks complete but is not.
assert_exit_in "doctor rejects --json with --only" "1" "$CLI" doctor --json --only storage

# --only must actually restrict the sections that run.
out="$("$CLI" doctor --only diskusage --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q 'Disk Usage'; then
    pass "--only ran the requested section"
else
    fail "--only did not run diskusage"
fi
if printf '%s' "$out" | grep -q '^== Configuration =='; then
    fail "--only ran a section it was not asked for"
else
    pass "--only suppressed the other sections"
fi

out="$("$CLI" doctor --skip storage --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q '^== Storage =='; then
    fail "--skip ran a skipped section"
else
    pass "--skip suppressed the named section"
fi

# --json must emit parseable JSON with the expected shape.
if [[ -n "$PYTHON" ]]; then
    json_out="$("$CLI" doctor --json 2>/dev/null || true)"
    if printf '%s' "$json_out" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
for key in ("host", "distro", "kernel", "summary", "findings", "suggestions"):
    assert key in d, "missing key: " + key
assert isinstance(d["findings"], list), "findings is not a list"
assert "errors" in d["summary"] and "warnings" in d["summary"], "bad summary"
for f in d["findings"]:
    assert f["status"] in ("ok", "warn", "error"), f"bad status: {f}"
' 2>/dev/null; then
        pass "doctor --json emits valid JSON with the expected shape"
    else
        fail "doctor --json output is not valid/complete JSON"
    fi

    # Nothing but the document may reach stdout.
    if printf '%s' "$json_out" | head -1 | grep -q '^{'; then
        pass "doctor --json starts the document on line 1"
    else
        fail "doctor --json leaked text before the document"
    fi
else
    fail "no python interpreter found - doctor --json shape not verified"
fi

# A timestamped report is written unless --no-report is passed.
before="$(find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null | wc -l | tr -d ' ')"
"$CLI" doctor --skip storage >/dev/null 2>&1 || true
after="$(find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$after" -gt "$before" ]]; then
    pass "doctor writes a timestamped report"
else
    fail "doctor did not write a report ($before -> $after)"
fi
# Reports must not contain raw escape codes.
latest="$(find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null | sort | tail -1)"
if [[ -n "$latest" ]] && ! grep -qP '\x1b\[' "$latest" 2>/dev/null; then
    pass "doctor report has escapes stripped"
else
    fail "doctor report contains ANSI escapes"
fi

before="$(find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null | wc -l | tr -d ' ')"
"$CLI" doctor --skip storage --no-report >/dev/null 2>&1 || true
after="$(find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null | wc -l | tr -d ' ')"
assert_equals "$after" "$before"

# New sections are reachable by name and listed in the usage text.
usage="$("$CLI" doctor --help 2>&1)"
for section in configuration applications system validation drift storage memory \
               swap systemd services session network pacman daemons battery diskusage; do
    if printf '%s' "$usage" | grep -qF "$section"; then
        pass "doctor --help lists $section"
    else
        fail "doctor --help omits $section"
    fi
done

assert_exit_in "doctor --only daemons" "0,1,2" "$CLI" doctor --only daemons --no-report
assert_exit_in "doctor --only battery"  "0,1,2" "$CLI" doctor --only battery --no-report
assert_exit_in "doctor --only diskusage" "0,1,2" "$CLI" doctor --only diskusage --no-report

# Every name in the usage text must be a name doctor_wants accepts. Any of
# 0/1/2 is a valid doctor result - a section run in isolation can legitimately
# report warnings or errors.
while read -r section; do
    [[ -z "$section" ]] && continue
    assert_exit_in "doctor --only $section" "0,1,2" "$CLI" doctor --only "$section" --no-report
done < <(printf '%s\n' "$usage" | sed -n '/^Sections:/,$p' | tail -n +2 | tr -s ' \t\n' '\n' | grep -v '^$')

# An unknown section name must be rejected. Silently running nothing would look
# exactly like a clean bill of health.
assert_exit_in "doctor rejects an unknown --only name" "1" "$CLI" doctor --only nosuchsection --no-report
assert_exit_in "doctor rejects an unknown --skip name" "1" "$CLI" doctor --skip nosuchsection --no-report
out="$("$CLI" doctor --only nosuchsection --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q 'Valid sections:'; then
    pass "doctor lists the valid sections when rejecting a name"
else
    fail "doctor did not list the valid sections"
fi
# A valid name inside a list must still work.
assert_exit_in "doctor accepts a name within a list" "0,1,2" "$CLI" doctor --only gpu,storage --no-report
# gpu must be independently selectable and must still run under session.
out="$("$CLI" doctor --only gpu --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q 'Hybrid GPU'; then
    pass "--only gpu selects the Hybrid GPU section"
else
    fail "--only gpu did not run Hybrid GPU"
fi

# A full run, kept for the duplicate-section check below.
full_out="$("$CLI" doctor --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
# gpu is a top-level section of its own, not nested in session. A full run
# must therefore show it exactly once.
n="$(grep -c '^== Hybrid GPU ==$' <<<"$full_out" || true)"
assert_equals "$n" "1"
out="$("$CLI" doctor --only session --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q 'Hybrid GPU'; then
    fail "--only session still ran the Hybrid GPU section"
else
    pass "--only session excludes Hybrid GPU"
fi
out="$("$CLI" doctor --skip gpu --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q 'Hybrid GPU'; then
    fail "--skip gpu still ran the Hybrid GPU section"
else
    pass "--skip gpu excludes Hybrid GPU"
fi

# ============================================
# Summary
# ============================================
log ""
log "========================================="
log "Passed : $PASSED"
log "Failed : $FAILED"
log "Finished: $(date)"
log "========================================="

((FAILED == 0))
