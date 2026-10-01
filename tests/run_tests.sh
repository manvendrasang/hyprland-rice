#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Test log file. A single fixed name (overwritten each run) rather than a
# timestamped one per run - a timestamped log accumulates forever and the
# pile makes it harder to find the run you actually care about. A copy of
# the most recent run's log is kept alongside it only if you ask for one
# via HYPRX_TEST_LOG_ARCHIVE=1.
TEST_LOG_DIR="$ROOT_DIR/tests"
TEST_LOG="$TEST_LOG_DIR/test-results.log"
: >"$TEST_LOG"

# Isolate tests from the real repo state
TEST_ROOT="$(mktemp -d)"
cp -r "$ROOT_DIR/config" "$TEST_ROOT/"

export HYPRX_CONFIG="$TEST_ROOT/config"
export HYPRX_SNAPSHOT_DIR="$TEST_ROOT/state/snapshots"
export HYPRX_FAILURE_LOG="$TEST_ROOT/state/hyprx-install.log"
export HYPRX_REPORT_FILE="$TEST_ROOT/state/HyprX-Install-Report.txt"
export HYPRX_TARGET_HOME="$TEST_ROOT/home"
export HYPRX_CONFIG_BACKUP_ROOT="$TEST_ROOT/state/config-backups"
export HYPRX_DEPLOYED_TARGETS_FILE="$TEST_ROOT/state/deployed-targets"
# These two were previously hardcoded to the real ~/.local/state/hyprx, so
# the suite used to write to (and read from) the user's actual state dir.
export HYPRX_LOGGER_DIR="$TEST_ROOT/state/log"
export HYPRX_RECOVERY_STATE_DIR="$TEST_ROOT/state/recovery"

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

# Run a command and echo its exit code without tripping `set -e`.
# The suite must survive a non-zero exit from anything it probes, so
# that one broken command cannot truncate the run (and the log file)
# before the remaining tests execute.
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

# ============================================
# Test: Bootstrap
# ============================================
log "Testing bootstrap..."
assert_equals true "$HYPRX_INITIALIZED"
assert_true test -d "$HYPRX_CONFIG"
assert_true test -d "$HYPRX_COMMANDS"

# ============================================
# Test: Config
# ============================================
log "Testing config..."
assert_equals default "$(hyprx_config_get THEME)"
hyprx_config_set THEME dark
hyprx_config_load
assert_equals dark "$HYPRX_CONFIG_THEME"
hyprx_config_set THEME default

# Config keys must not leak into the global namespace. This is the whole
# point of prefixing them: config/hyprx.conf used to set a bare
# PACKAGE_MANAGER=auto global that collided with the detected value the
# package layer reads.
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

# ============================================
# Test: Detection
# ============================================
log "Testing detection..."
# Distro and package manager must resolve. CPU/GPU vendor depend on lscpu
# and lspci, which a minimal container may not ship - assert they were
# *probed* (i.e. defined, possibly "unknown") rather than non-empty, so a
# missing tool is a skip rather than a confusing failure.
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

# ============================================
# Test: Logging
# ============================================
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

# ============================================
# Test: Progress
# ============================================
log "Testing progress..."
for i in {1..10}; do hyprx_progress_bar "$i" 10 >/dev/null; done
hyprx_table_header
hyprx_table_row "Test" "OK"

# ============================================
# Test: Packages
# ============================================
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

# ============================================
# Test: Requirements
# ============================================
log "Testing requirements..."
HINT="$(hyprx_requirements_get_hint steam)"
assert_not_empty "$HINT"
assert_true grep -q "multilib" <<< "$HINT"
UNKNOWN_HINT="$(hyprx_requirements_get_hint totally-not-a-real-package)"
assert_equals "" "$UNKNOWN_HINT"

# ============================================
# Test: Replacements
# ============================================
log "Testing replacements..."
if [[ -f "$HYPRX_DATABASE/package-replacements.conf" ]]; then
    while IFS='=' read -r old new; do
        [[ -z "$old" ]] && continue
        [[ "$old" =~ ^# ]] && continue
        replacement="$(hyprx_replacements_get "$old")"
        [[ "$replacement" == "$new" ]] && pass "$old -> $new" || fail "$old -> $new (got: $replacement)"
    done < "$HYPRX_DATABASE/package-replacements.conf"
fi

# ============================================
# Test: Installer Pipeline
# ============================================
log "Testing installer pipeline..."
[[ "${HYPRX_INITIALIZED:-false}" == "true" ]]
hyprx_resolver_resolve
[[ ${#HYPRX_INSTALL_QUEUE[@]} -gt 0 ]]
UNIQUE_COUNT="$(printf "%s\n" "${HYPRX_INSTALL_QUEUE[@]}" | sort -u | wc -l)"
[[ "$UNIQUE_COUNT" -eq "${#HYPRX_INSTALL_QUEUE[@]}" ]]
pass "Installer pipeline OK"

# ============================================
# Test: Config Deployment
# ============================================
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

# ============================================
# Test: Orphaned Target Cleanup
# ============================================
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

# ============================================
# Test: Snapshot/Rollback
# ============================================
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

# ============================================
# Test: Retry
# ============================================
log "Testing retry..."
hyprx_retry 1 true
pass "Retry OK"

# ============================================
# Test: Report Generation
# ============================================
log "Testing report generation..."
HYPRX_INSTALL_FAILED=()
HYPRX_INSTALL_INSTALLED=()
HYPRX_INSTALL_SKIPPED=()
export HYPRX_REPORT_FILE="/tmp/hyprx-test-report.txt"
hyprx_report_generate >/dev/null
assert_file_exists "$HYPRX_REPORT_FILE"
pass "Report generation OK"

# ============================================
# Test: Dry run
# ============================================
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

# ============================================
# Test: Clean sandbox
# ============================================
# HYPRX_CLEAN_ROOT lets the real deletion logic run against a throwaway
# tree. Without it, `hyprx clean` could only ever be tested via --dry-run,
# leaving the actual rm/find calls unexercised.
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

# ============================================
# Test: Install/Uninstall
# ============================================
log "Testing install/uninstall..."
INSTALL_TEST_ROOT="$(mktemp -d)"
export HYPRX_INSTALL_DIR="$INSTALL_TEST_ROOT/share/hyprx"
export HYPRX_BIN_DIR="$INSTALL_TEST_ROOT/bin"
bash "$ROOT_DIR/install.sh" >/dev/null
assert_true test -d "$HYPRX_INSTALL_DIR"
assert_true test -f "$HYPRX_INSTALL_DIR/bin/hyprx"
assert_true test -L "$HYPRX_BIN_DIR/hyprx"
assert_true test -L "$HYPRX_BIN_DIR/prime-run"
assert_false test -d "$HYPRX_INSTALL_DIR/.git"
"$HYPRX_BIN_DIR/hyprx" help >/dev/null
bash "$ROOT_DIR/install.sh" >/dev/null
assert_true test -f "$HYPRX_INSTALL_DIR/bin/hyprx"
bash "$ROOT_DIR/uninstall.sh" >/dev/null
assert_false test -d "$HYPRX_INSTALL_DIR"
assert_false test -e "$HYPRX_BIN_DIR/hyprx"
assert_false test -e "$HYPRX_BIN_DIR/prime-run"
rm -rf "$INSTALL_TEST_ROOT"
pass "Install/uninstall OK"

# ============================================
# Test: CLI
# ============================================
log "Testing CLI..."

# Read-only / non-destructive probes only. `hyprx clean` (no flags) really
# does vacuum the journal, wipe the pacman cache, clear thumbnail caches
# and rm files out of /tmp - never invoke that from a test run.
assert_exit_in "hyprx (no args)"            "0"      "$CLI"
assert_exit_in "hyprx help"                 "0"      "$CLI" help
assert_exit_in "hyprx doctor"               "0,1,2"  "$CLI" doctor
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
assert_exit_in "hyprx clean --help"          "0"      "$CLI" clean --help
assert_exit_in "hyprx clean --bogus"        "1"      "$CLI" clean --bogus
pass "CLI OK"

# ============================================
# Test: Permissions
# ============================================
log "Checking permissions..."
find "$ROOT_DIR/bin" "$ROOT_DIR/scripts" -type f | while IFS= read -r file; do
    [[ -x "$file" ]] || fail "$file is not executable"
done
pass "Permissions OK"

# ============================================
# Test: Scripts
# ============================================
log "Checking helper scripts..."
for script in backup-config.sh dev-sync.sh reload-hypr.sh reload-waybar.sh; do
    [[ -x "$ROOT_DIR/scripts/$script" ]] && pass "$script executable" || fail "$script not executable"
done
pass "Scripts OK"

# ============================================
# Test: ShellCheck
# ============================================
log "Running ShellCheck..."
SC_FAILED=0
while IFS= read -r -d '' file; do
    if ! shellcheck -x -e SC1090,SC1091,SC2010,SC2015,SC2034,SC2086 "$file" >/dev/null 2>&1; then
        fail "ShellCheck: $file"
        SC_FAILED=1
    fi
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -path "$ROOT_DIR/build" -prune -o -path "$ROOT_DIR/.cache" -prune -o -name "*.sh" -print0)
[[ $SC_FAILED -eq 0 ]] && pass "ShellCheck OK"

# ============================================
# Test: Syntax
# ============================================
log "Checking syntax..."
SYN_FAILED=0
while IFS= read -r -d '' file; do
    if ! bash -n "$file" 2>/dev/null; then
        fail "Syntax: $file"
        SYN_FAILED=1
    fi
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -path "$ROOT_DIR/build" -prune -o -path "$ROOT_DIR/.cache" -prune -o -name "*.sh" -print0)
[[ $SYN_FAILED -eq 0 ]] && pass "Syntax OK"

# ============================================
# Test: Source
# ============================================
log "Testing source..."
for _ in $(seq 25); do
    bash -c "source \"$ROOT_DIR/lib/bootstrap.sh\"" >/dev/null 2>&1 || fail "Bootstrap source failed"
done
pass "Bootstrap sourcing OK"

# ============================================
# Test: Smoke
# ============================================
log "Running smoke test..."
hyprx_resolver_resolve
[[ ${#HYPRX_INSTALL_QUEUE[@]} -gt 0 ]]
assert_file_exists "$ROOT_DIR/services.list"
pass "Smoke test OK"

# ============================================
# Test: Coverage
# ============================================
log "Checking library coverage..."
missing=0
while IFS= read -r file; do
    name="$(basename "$file")"

    # bootstrap.sh is the entry point - it is the thing that sources
    # everything else, so it cannot (and should not) list itself.
    [[ "$name" == "bootstrap.sh" ]] && continue

    # Every other lib file must be reachable from bootstrap.sh, otherwise
    # it is dead weight that nothing ever loads. Note the source lists use
    # a loop variable (`source "$HYPRX_LIB/$file"`), so match on the bare
    # filename appearing anywhere in bootstrap.sh rather than on a
    # `source` line.
    if ! grep -qF "$name" "$ROOT_DIR/lib/bootstrap.sh" 2>/dev/null; then
        fail "UNCOVERED: $name (not listed in lib/bootstrap.sh)"
        missing=$((missing + 1))
    fi
done < <(find "$ROOT_DIR/lib" -name '*.sh' -type f | sort)
[[ $missing -eq 0 ]] && pass "Coverage OK"

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
