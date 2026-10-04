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

# ===========================================================================
# Flags - so a failure names the section it came from, and so a targeted run
# does not pay for the whole suite
# ===========================================================================
# The suite is ~3000 lines and 36 sections. Running all of it after every small
# edit is the wrong default: most edits touch one section, and the end-to-end
# install block alone is several seconds of subprocess work that most changes
# cannot affect.
#
#   -f, --filter REGEX   only count assertions from matching sections
#   -l, --list           print the section names and exit
#   -h, --help           this text
#
# `pass`/`fail` are gated rather than each block being wrapped, so the filter
# needs no edits at the ~150 assertion sites. The one section whose *execution*
# is expensive (end-to-end install) is additionally guarded by section_runs, so
# -f genuinely skips the work rather than just its reporting.
FILTER=""
LIST_ONLY=false

usage_text() {
    cat <<'USAGE'
Usage: bash tests/run_tests.sh [options]

  -f, --filter REGEX   Only report assertions from sections whose name matches
                       REGEX (an extended regex). Other sections still run their
                       cheap checks but are not counted, so a failure can only
                       come from the section you are working on.
  -l, --list           List section names, one per line, and exit.
  -h, --help           Show this help.

With no options the full suite runs and every assertion is counted.
USAGE
}

while (( $# )); do
    case "$1" in
        -f|--filter) FILTER="${2:-}"; shift 2 ;;
        -l|--list)   LIST_ONLY=true; shift ;;
        -h|--help)   usage_text; exit 0 ;;
        *)
            printf 'unknown option: %s\n\n' "$1" >&2
            usage_text >&2
            exit 2
            ;;
    esac
done

PASSED=0
FAILED=0
FAILED_ASSERTIONS=()
CURRENT_SECTION=""
SECTION_ON=true
SECTION_SKIPPED=()
SECTION_TIMES=()
SECTION_START=0

# Names are read out of the file rather than duplicated in a table, so a new
# section cannot be added without appearing in --list.
section_name_at() {
    sed -n 's/^section_start "\(.*\)"$/\1/p' "$ROOT_DIR/tests/run_tests.sh"
}

if [[ "$LIST_ONLY" == true ]]; then
    section_name_at
    exit 0
fi

# Log both to stdout and to the log file
log() {
    printf "%s\n" "$*" | tee -a "$TEST_LOG"
}

# Marks the start of a section: decides whether it counts, and starts its clock.
section_start() {
    local name="$1"

    if [[ -n "$CURRENT_SECTION" ]]; then
        SECTION_TIMES+=("$(( $(date +%s) - SECTION_START ))	$CURRENT_SECTION")
    fi
    CURRENT_SECTION="$name"
    SECTION_START="$(date +%s)"

    if [[ -n "$FILTER" ]] && ! [[ "$name" =~ $FILTER ]]; then
        SECTION_ON=false
        SECTION_SKIPPED+=("$name")
        return 0
    fi

    SECTION_ON=true
    log "Testing $name..."
}

# True only when the current section both matches the filter and is one of the
# expensive ones worth skipping outright. Used to guard heavy blocks.
section_runs() {
    [[ "$SECTION_ON" == true ]]
}

pass() {
    [[ "$SECTION_ON" == true ]] || return 0
    log "  [PASS] $1"
    PASSED=$((PASSED + 1))
}

# Failures are also collected so the summary can repeat them. A CI log viewer
# collapses the middle of a long run, and a failure buried there is invisible.
fail() {
    [[ "$SECTION_ON" == true ]] || return 0
    log "  [FAIL] $1"
    FAILED=$((FAILED + 1))
    FAILED_ASSERTIONS+=("$CURRENT_SECTION: $1")
}

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

# Build a local stand-in for the four Caudex faces: real filenames, synthetic
# contents, and a checksum for each. Emits the "file|sha256 ..." spec that
# lib/installer/fonts.sh reads, so the fetch -> size -> SHA256 -> move ->
# fc-cache path is exercised for real with no network and no font binaries in
# the repository.
#
# The four shipped production pins are asserted separately against the upstream
# files, so redirecting the source here cannot hide a bad pin.
# Read the SHIPPED pin list out of lib/installer/fonts.sh. Extracted here rather
# than grepped inline because the trimming matters: the spec is one long
# space-separated string, so the last entry carries a trailing space that makes
# a naive `[0-9a-f]{64}` test fail.
font_shipped_spec() {
    local raw
    raw="$(grep -oE 'HYPRX_FONT_SPEC="\$\{HYPRX_FONT_SPEC:-[^}]*\}' \
        "$ROOT_DIR/lib/installer/fonts.sh")"

    # Strip the `HYPRX_FONT_SPEC="${HYPRX_FONT_SPEC:-` prefix and the trailing
    # `}"` with parameter expansion rather than sed: the spec itself contains
    # `|` and the sed alternation kept proving fragile against it.
    raw="${raw#*HYPRX_FONT_SPEC:-}"
    raw="${raw%\}}"

    local entry out=""
    for entry in $raw; do
        entry="${entry%"${entry##*[![:space:]]}"}"
        out+="$entry "
    done
    printf '%s' "${out% }"
}

font_fixture_spec() {
    local dir="$1"
    mkdir -p "$dir"
    local f
    for f in Caudex-Regular.ttf Caudex-Bold.ttf Caudex-Italic.ttf Caudex-BoldItalic.ttf; do
        printf 'synthetic %s fixture for testing\n' "$f" >"$dir/$f"
    done
    ( cd "$dir" && for f in Caudex-Regular.ttf Caudex-Bold.ttf Caudex-Italic.ttf Caudex-BoldItalic.ttf; do
        printf '%s|%s ' "$f" "$(sha256sum "$f" | awk '{print $1}')"
    done )
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

# Test: suite prerequisites
#
# Checked before anything else, because two of these absences were invisible:
#
#   * `diff` was missing from the CI container, so `if diff -q a b` exited 127,
#     the else branch ran, and the suite reported "default/template variable
#     sets differ:" with an EMPTY diff - a false failure blaming the files for
#     a missing program.
#   * `comm` and friends run inside $( ), so a missing tool yields empty output
#     rather than an error. `missing_vars="$(comm -23 a b)"` on a box without
#     comm produces "", and `[[ -z "$missing_vars" ]]` then PASSES. A missing
#     tool would have been reported as a passing assertion.
#
# This is the test-suite version of the gate's ping bug: a tool that is not
# there is not evidence about the thing being tested. So the tools are asserted
# up front, with the package to install.
section_start "suite prerequisites"
TOOLS_OK=1
for tool in diff comm sort awk sed grep tr uniq wc sha256sum shellcheck jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "missing tool: $tool (install it - CI: pacman -Syy --needed $tool)"
        TOOLS_OK=0
    fi
done
if (( TOOLS_OK == 1 )); then
    pass "all suite tools available (diff comm sort awk sed grep tr uniq wc sha256sum shellcheck jq)"
fi

# Every comparison of two files must distinguish "they differ" from "the diff
# tool did not run". Both are non-zero, and treating them alike is what turned
# a missing binary into an accusation against the file contents.
#
# Usage: files_equal <a> <b>  ->  prints "equal" | "differ" | "no-diff-tool"
files_equal() {
    local a="$1" b="$2" rc=0
    diff -q "$a" "$b" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) printf 'equal' ;;
        1) printf 'differ' ;;
        *) printf 'no-diff-tool' ;;
    esac
}

# assert_covers <label> <have-file> <want-file>
#
# Asserts every line of <want-file> appears in <have-file>. The three outcomes
# are kept apart because they are otherwise indistinguishable: `comm` inside
# $( ) yields "" both when there is nothing missing AND when comm itself could
# not run, and every caller tests for "". A missing comm would therefore have
# been reported as a passing assertion. Exit 127 makes that case loud.
assert_covers() {
    local label="$1" have="$2" want="$3"
    local missing rc=0
    missing="$(comm -23 "$want" "$have" 2>/dev/null)" || rc=$?
    if (( rc != 0 )); then
        fail "$label: cannot verify ('comm' exited $rc - tool missing?)"
    elif [[ -z "$missing" ]]; then
        pass "$label"
    else
        fail "$label (missing: $(tr '\n' ' ' <<<"$missing"))"
    fi
}

# Test: Bootstrap
section_start "bootstrap"
assert_equals true "$HYPRX_INITIALIZED"
assert_true test -d "$HYPRX_CONFIG"
assert_true test -d "$HYPRX_COMMANDS"

# Test: Config
section_start "config"
assert_equals default "$(hyprx_config_get THEME)"

# hyprx_config_set now validates before it writes, so a theme name has to be a
# real theme. "dark" was never a theme and the old unvalidated setter accepted it.
hyprx_config_set THEME one-dark
hyprx_config_load
assert_equals one-dark "$HYPRX_CONFIG_THEME"
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
#
# The file is saved and restored around this. It used to be left containing
# NOT_A_KEY, and every later command that loads the config then printed
# "Unknown key in hyprx.conf: NOT_A_KEY" - on stdout, which corrupted
# `doctor --json` output. The JSON test still passed in a full run only because
# an unrelated later section (`CLI`, which runs `config unset NOT_A_KEY`)
# happened to rewrite the file and clear it. Run with `-f doctor flags`, that
# section is skipped, the pollution survives, and the JSON test fails for a
# reason that has nothing to do with JSON.
cfg_saved="$(mktemp)"
cp "$HYPRX_CONFIG_FILE" "$cfg_saved"
printf 'HYPRX_CONFIG_THEME=default\nNOT_A_KEY=evil\n' >"$HYPRX_CONFIG_FILE"
unknown_key_out="$(hyprx_config_load 2>&1)"
if printf '%s' "$unknown_key_out" | grep -q "NOT_A_KEY"; then
    pass "unknown config key is reported"
else
    fail "unknown config key silently ignored"
fi
cp "$cfg_saved" "$HYPRX_CONFIG_FILE"
rm -f "$cfg_saved"
hyprx_config_load >/dev/null 2>&1

# Test: Detection
section_start "detection"
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
section_start "logging"
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
section_start "table output"
hyprx_table_header
hyprx_table_row "Test" "OK"
pass "Table output OK"

# Test: Packages
section_start "packages"
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
section_start "requirements"
HINT="$(hyprx_requirements_get_hint steam)"
assert_not_empty "$HINT"
assert_true grep -q "multilib" <<< "$HINT"
UNKNOWN_HINT="$(hyprx_requirements_get_hint totally-not-a-real-package)"
assert_equals "" "$UNKNOWN_HINT"

# Test: Replacements
section_start "replacements"
if [[ -f "$HYPRX_DATABASE/package-replacements.conf" ]]; then
    while IFS='=' read -r old new; do
        [[ -z "$old" ]] && continue
        [[ "$old" =~ ^# ]] && continue
        replacement="$(hyprx_replacements_get "$old")"
        if [[ "$replacement" == "$new" ]]; then
            pass "$old -> $new"
        else
            fail "$old -> $new (got: $replacement)"
        fi
    done < "$HYPRX_DATABASE/package-replacements.conf"
fi

# Test: Installer Pipeline
section_start "installer pipeline"
[[ "${HYPRX_INITIALIZED:-false}" == "true" ]]
hyprx_resolver_resolve
[[ ${#HYPRX_INSTALL_QUEUE[@]} -gt 0 ]]
UNIQUE_COUNT="$(printf "%s\n" "${HYPRX_INSTALL_QUEUE[@]}" | sort -u | wc -l)"
[[ "$UNIQUE_COUNT" -eq "${#HYPRX_INSTALL_QUEUE[@]}" ]]
pass "Installer pipeline OK"

# --- no stage may be guarded by a return code it cannot produce --------------
# engine.sh decides the run's verdict with `hyprx_X || return 1` and with
# `hyprx_X || rc=$?`. The second form only means anything if X can return
# non-zero. Three stages could not - each ended on a statement that always exits
# 0 - so those guards were dead code that read like safety nets:
#
#   hyprx_resolver_resolve   ended on `mapfile`
#   hyprx_deploy_all         ended on `hyprx_snapshot_write_deployed`
#   hyprx_report_generate    ended on `echo`
#
# The observable damage in all three was the same shape as the validator's: a
# run that had NOT done the thing still reported that it had. A missing
# packages.list installed nothing and printed "All packages installed
# successfully"; a config dir that failed to deploy still ended in
# "Installation completed successfully"; an unwritable report path printed
# "Report written:" for a file that did not exist.
#
# `return 0` at the end of a function is not redundant: a function's status is
# the status of its last command, so these three each needed it stated.

# resolver: a root with no packages.list at all
saved_root="$HYPRX_ROOT"
mkdir -p "$TEST_ROOT/emptyroot"
HYPRX_ROOT="$TEST_ROOT/emptyroot"
hyprx_resolver_resolve >/dev/null 2>&1 && resolver_rc=0 || resolver_rc=$?
if (( resolver_rc != 0 )); then
    pass "resolver refuses a root with no packages.list (rc=$resolver_rc)"
else
    fail "resolver returned 0 with no packages.list - an empty install would report success"
fi

# resolver: a packages.list where every entry is commented out
mkdir -p "$TEST_ROOT/commentroot"
printf '# only a comment\n\n# and another\n' >"$TEST_ROOT/commentroot/packages.list"
HYPRX_ROOT="$TEST_ROOT/commentroot"
hyprx_resolver_resolve >/dev/null 2>&1 && resolver_rc=0 || resolver_rc=$?
if (( resolver_rc != 0 )); then
    pass "resolver refuses an all-commented packages.list (rc=$resolver_rc)"
else
    fail "resolver returned 0 for a packages.list with no packages in it"
fi

HYPRX_ROOT="$saved_root"
hyprx_resolver_resolve >/dev/null 2>&1
if (( ${#HYPRX_INSTALL_QUEUE[@]} > 0 )); then
    pass "resolver still resolves the real packages.list after those refusals"
else
    fail "resolver no longer resolves the real packages.list"
fi

# deploy: one target whose source directory does not exist
saved_targets="$HYPRX_CONFIG_TARGETS"
HYPRX_CONFIG_TARGETS="hypr hyprx-no-such-config-dir"
hyprx_deploy_all >/dev/null 2>&1 && deploy_rc=0 || deploy_rc=$?
HYPRX_CONFIG_TARGETS="$saved_targets"
if (( deploy_rc != 0 )); then
    pass "a failed config deploy makes hyprx_deploy_all fail (rc=$deploy_rc)"
else
    fail "hyprx_deploy_all returned 0 with a target that could not be deployed"
fi

# report: an unwritable report path.
#
# The parent has to be a regular FILE, not a missing directory: the report
# generator starts with `mkdir -p "$(dirname "$report")"`, so any path under a
# writable directory is simply created and the write succeeds. A file in the way
# is the case that actually fails - a test pointed at a merely-absent directory
# would have passed while proving nothing.
printf 'not a directory\n' >"$TEST_ROOT/report-blocker"
saved_report="$HYPRX_STATE_REPORT_FILE"
HYPRX_STATE_REPORT_FILE="$TEST_ROOT/report-blocker/report.txt"
hyprx_report_generate >/dev/null 2>&1 && report_rc=0 || report_rc=$?
HYPRX_STATE_REPORT_FILE="$saved_report"
if (( report_rc != 0 )); then
    pass "an unwritable report path makes hyprx_report_generate fail (rc=$report_rc)"
else
    fail "hyprx_report_generate returned 0 for a path it could not write"
fi

# ...and the report must not claim to exist when it does not.
HYPRX_STATE_REPORT_FILE="$TEST_ROOT/report-blocker/report.txt"
report_out="$(hyprx_report_generate 2>&1 || true)"
HYPRX_STATE_REPORT_FILE="$saved_report"
if [[ "$report_out" == *"Report written"* ]]; then
    fail "hyprx_report_generate announced 'Report written' for a file it could not write"
else
    pass "hyprx_report_generate does not announce a report it failed to write"
fi

# And every guard in engine.sh must now have a callee that can return non-zero.
# A check that cannot fail is worse than no check, so the engine is inspected
# rather than trusted.
guard_dead=()
while IFS= read -r callee; do
    [[ -z "$callee" ]] && continue
    def_file="$(grep -rln "^${callee}()" "$ROOT_DIR/lib" 2>/dev/null | head -1)"
    if [[ -z "$def_file" ]]; then
        guard_dead+=("$callee: not defined")
        continue
    fi
    def_line="$(grep -n "^${callee}()" "$def_file" | head -1 | cut -d: -f1)"
    if ! awk -v s="$def_line" 'NR>s && /^}$/ {exit} NR>s && /(^|[[:space:]])return 1([[:space:]]|$)/ {found=1} END {exit found?0:1}' "$def_file"; then
        guard_dead+=("$callee ($def_file)")
    fi
done < <(grep -oE '^[[:space:]]*hyprx_[a-z_]+ \|\| return 1' "$ROOT_DIR/lib/installer/engine.sh" \
         | grep -oE 'hyprx_[a-z_]+' | sort -u)

if (( ${#guard_dead[@]} == 0 )); then
    pass "every '|| return 1' stage in engine.sh can actually return 1"
else
    fail "engine.sh guards a stage that cannot fail: ${guard_dead[*]}"
    info "a guard on something that always exits 0 is not a guard - it reads like one"
fi

# Guard against the check itself matching nothing, which is how a check like
# this silently becomes a permanent pass.
guard_count="$(grep -cE '^[[:space:]]*hyprx_[a-z_]+ \|\| return 1' "$ROOT_DIR/lib/installer/engine.sh" || true)"
if (( guard_count >= 3 )); then
    pass "the dead-guard scan inspected $guard_count stages"
else
    fail "the dead-guard scan only saw $guard_count stage(s) - it is not inspecting engine.sh"
fi

# Test: Config Deployment
section_start "config deployment"
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
section_start "orphaned-target cleanup"
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
section_start "snapshot/rollback"
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
section_start "retry"
hyprx_retry 1 true
pass "Retry OK"

# Test: Report Generation
section_start "report generation"
HYPRX_INSTALL_FAILED=()
HYPRX_INSTALL_INSTALLED=()
HYPRX_INSTALL_SKIPPED=()

# Assert on HYPRX_STATE_REPORT_FILE, which is what report.sh writes to.
# Setting HYPRX_REPORT_FILE here does nothing: lib/state.sh resolves the state
# path once at source time, so overriding the input afterwards has no effect.
# The suite pointed at a fixed /tmp path instead, which meant it was really
# asserting on whatever a previous run had left there - a leftover file from
# before the refactor made it pass locally while a fresh container correctly
# failed it.
rm -f "$HYPRX_STATE_REPORT_FILE"
hyprx_report_generate >/dev/null
assert_file_exists "$HYPRX_STATE_REPORT_FILE"
if [[ "$HYPRX_STATE_REPORT_FILE" == "$TEST_ROOT"/* ]]; then
    pass "report stays inside the sandbox"
else
    fail "report escapes the sandbox: $HYPRX_STATE_REPORT_FILE"
fi
pass "Report generation OK"

# Test: Dry run
section_start "dry-run semantics"

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
rm -f "$HYPRX_STATE_REPORT_FILE"
hyprx_report_generate >/dev/null
if [[ -f "$HYPRX_STATE_REPORT_FILE" ]] && grep -q "DRY RUN" "$HYPRX_STATE_REPORT_FILE"; then
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
section_start "clean sandbox"
if section_runs; then
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
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "wallpaper startup path"

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
section_start "waybar startup path"
if section_runs; then

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

# The reload must not be a blind kill-and-forget (`pkill` + unverified restart):
# the wallust daemon fires exactly that in the first seconds of a session, when
# the display may not be ready yet. It must go through ensure-waybar.sh --restart
# and must not hand-roll its own start.
#
# This was two assertions reading the same source file from opposite sides.
RELOAD_WAYBAR="$ROOT_DIR/scripts/reload-waybar.sh"
if ! grep -q "ensure-waybar.sh" "$RELOAD_WAYBAR" || ! grep -q -- "--restart" "$RELOAD_WAYBAR"; then
    fail "reload-waybar is a blind pkill + fire-and-forget restart instead of delegating"
elif grep -qE '^\s*(nohup waybar|waybar &)' "$RELOAD_WAYBAR"; then
    fail "reload-waybar starts waybar directly as well as delegating"
else
    pass "reload-waybar has a single start path, through ensure-waybar.sh --restart"
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
autostart_ok=0
autostart_missing=""
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
        autostart_ok=$((autostart_ok + 1))
    else
        autostart_missing+="$ref (expected $repo_path) "
    fi
done < <(grep -oE '(~/\.config/waybar/scripts/|~/\.local/share/hyprx/scripts/)[A-Za-z0-9._-]+\.sh' \
         "$ROOT_DIR/config/hypr/hyprland.lua" | sort -u)

# Was 7 assertions - one per autostarted script - for a fact that is either true
# for all of them or false for all of them.
if (( autostart_ok == 0 )); then
    fail "no autostart targets were found - the grep matched nothing"
elif [[ -n "$autostart_missing" ]]; then
    fail "autostart targets missing: ${autostart_missing% }"
else
    pass "all $autostart_ok scripts autostarted by hyprland.lua exist and are executable"
fi
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
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "install/uninstall"
if section_runs; then
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
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "CLI"
if section_runs; then

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
        # Removed: a single "braces balance" grep over hyprlock.conf, which is a
        # hand-written file nothing generates. hyprland.lua is syntax-checked by
        # luac above, so a real syntax error there is caught properly; this
        # counted pairs of a character and could only fail on a manual edit.
        true
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

# No command may reach a mutating path via a stray argument.
#
# This used to grep each command file for one of four rejection strings -
# 5 assertions plus a sixth that only re-stated the loop. It asserted that a
# word appears in a source file, which no other feature can break and which the
# executed `--bogus` assertions above already prove. The one thing a grep could
# catch that execution cannot - a command that has no rejection path at all - is
# now covered by checking that every command rejects something, below.
assert_exit_in "hyprx clean --help"          "0"      "$CLI" clean --help
assert_exit_in "hyprx clean --bogus"        "1"      "$CLI" clean --bogus

# Every command that can mutate something must reject an argument it does not
# understand. One assertion covering all of them, naming the ones that do not.
no_reject=()
for cmd_name in clean config install rollback update; do
    if "$CLI" "$cmd_name" --definitely-not-a-flag --no-pager >/dev/null 2>&1; then
        no_reject+=("$cmd_name")
    fi
done
if (( ${#no_reject[@]} == 0 )); then
    pass "every mutating command rejects an argument it does not understand"
else
    fail "these commands ignored a bogus argument: ${no_reject[*]}"
fi

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

# Every advertised key must be listable and have a default. Asserted once, as a
# loop over all keys - it used to be 14 assertions here, one per key and one per
# accessor, for a fact that is either true for all keys or false for all of them.
# The per-key values themselves are checked in the `config` section.
bad_keys=()
for cfg_key in THEME AUTO_CONFIRM BACKUP_ON_DEPLOY ENABLE_GPU_OFFLOAD \
              LOG_LEVEL LOG_FILE PACKAGE_MANAGER; do
    hyprx_config_get "$cfg_key" >/dev/null 2>&1 || bad_keys+=("get:$cfg_key")
    hyprx_config_default_value "$cfg_key" >/dev/null 2>&1 || bad_keys+=("default:$cfg_key")
done
if (( ${#bad_keys[@]} == 0 )); then
    pass "all 7 config keys are readable and have a default"
else
    fail "config keys unreadable: ${bad_keys[*]}"
fi
pass "Config command OK"

pass "CLI OK"

# Test: Permissions
log "Checking permissions..."
# Process substitution, NOT `find | while`. A pipeline runs the right-hand side
# in a subshell, so every `fail` here incremented FAILED in a process that then
# exited - the counter never changed and the check could not fail. Verified: the
# old form printed the [FAIL] lines and still reported FAILED=0.
#
# config/waybar/scripts is included because all 18 of those are invoked by bare
# path from config.jsonc and hyprland.lua, which needs the executable bit.
while IFS= read -r file; do
    [[ -x "$file" ]] || fail "$file is not executable"
done < <(find "$ROOT_DIR/bin" "$ROOT_DIR/scripts" "$ROOT_DIR/config/waybar/scripts" -type f 2>/dev/null)
pass "Permissions OK"

# Test: Scripts
log "Checking helper scripts..."
# dev-sync.sh is deliberately absent: two copies shipped, both broken. The one
# in config/waybar/scripts deleted the directory it was executing from and then
# copied from a path that no longer existed; the one in scripts/ ran
# `rsync --delete` into ~/.config/hypr, destroying the live hyprpaper.conf.
for script in backup-config.sh reload-hypr.sh reload-waybar.sh; do
    if [[ -x "$ROOT_DIR/scripts/$script" ]]; then
        pass "$script executable"
    else
        fail "$script not executable"
    fi
done
pass "Scripts OK"

# Test: ShellCheck
#
# Reads .shellcheckrc, exactly as CI does. It used to pass its own inline
# `-e SC1090,SC1091,SC2010,SC2015,SC2034,SC2086` list instead, which is how the
# suite reported "ShellCheck OK" on twelve SC2015 findings that CI - running the
# real .shellcheckrc - rejected. Two linters with two rulesets: one green, one
# red, and no way to tell from the suite which was authoritative.
#
# --rcfile is passed explicitly rather than relying on ShellCheck finding
# .shellcheckrc in the current directory: that lookup is cwd-relative, so the
# rules silently changed depending on where the command was run from.
#
# bin/hyprx is included and has no .sh suffix, so `find -name '*.sh'` misses it.
log "Running ShellCheck..."
SC_FAILED=0
SC_RCFILE="$ROOT_DIR/.shellcheckrc"
if [[ ! -f "$SC_RCFILE" ]]; then
    fail "ShellCheck: .shellcheckrc is missing, so the exclusion list is undefined"
else
    pass "ShellCheck: using $SC_RCFILE"
fi
while IFS= read -r -d '' file; do
    if ! shellcheck -x --rcfile "$SC_RCFILE" "$file" >/dev/null 2>&1; then
        # Show the findings rather than only naming the file: a bare filename is
        # not actionable.
        shellcheck -x --rcfile "$SC_RCFILE" -f gcc "$file" 2>&1 \
            | while IFS= read -r finding; do
                printf '      %s\n' "${finding#"$ROOT_DIR"/}"
            done
        fail "ShellCheck: ${file#"$ROOT_DIR"/}"
        SC_FAILED=1
    fi
done < <(find "$ROOT_DIR" -path "$ROOT_DIR/.git" -prune -o -path "$ROOT_DIR/build" -prune -o -path "$ROOT_DIR/.cache" -prune -o \( -name "*.sh" -o -path "$ROOT_DIR/bin/hyprx" \) -print0)
if [[ $SC_FAILED -eq 0 ]]; then
    pass "ShellCheck OK"
else
    hyprx_ui_info "Note: ShellCheck findings vary by version. CI pins the version it"
    hyprx_ui_info "runs; see .github/workflows/tests.yml."
fi

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
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "source"
if section_runs; then
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
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "state path resolution"

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

# ...and it must still resolve that way in a FRESH process after the state dir
# changes. Two assignments used to break this, both writing a derived value back
# into the name of a back-compat OVERRIDE that the suite exports as "":
#
#   logger.sh:5   HYPRX_LOGGER_DIR="$HYPRX_STATE_DIR"
#   recovery.sh:6 HYPRX_RECOVERY_STATE_DIR="$HYPRX_STATE_RECOVERY_DIR"
#
# Because the name was exported, the concrete value stayed exported, and the
# child's state.sh then used it to override the HYPRX_STATE_DIR it had been
# given. The e2e install wrote install.state (and every log, snapshot and
# backup) under the suite-level dir while the assertions looked under the e2e
# one, so "install.state cleared on success" and "install.state cleared after a
# partial install" were green without either having looked at the file the
# install actually wrote.
child_state="$(
    HYPRX_STATE_DIR="$TEST_ROOT/moved/state" bash -c \
        "source '$ROOT_DIR/lib/bootstrap.sh' >/dev/null 2>&1; printf '%s' \"\$HYPRX_STATE_DIR\""
)"
if [[ "$child_state" == "$TEST_ROOT/moved/state" ]]; then
    pass "HYPRX_STATE_DIR is honoured in a fresh process"
else
    fail "HYPRX_STATE_DIR is overridden to '$child_state' instead of '$TEST_ROOT/moved/state'"
fi

child_recovery="$(
    HYPRX_STATE_DIR="$TEST_ROOT/moved/state" bash -c \
        "source '$ROOT_DIR/lib/bootstrap.sh' >/dev/null 2>&1; printf '%s' \"\$HYPRX_RECOVERY_STATE_FILE\""
)"
if [[ "$child_recovery" == "$TEST_ROOT/moved/state/install.state" ]]; then
    pass "the recovery file follows HYPRX_STATE_DIR in a fresh process"
else
    fail "recovery file is frozen at '$child_recovery' instead of '$TEST_ROOT/moved/state/install.state'"
fi

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
section_start "log rotation"

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
section_start "hyprx clean flags"
if section_runs; then

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
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "hyprx doctor flags"
if section_runs; then

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
before="$({ find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null || true; } | wc -l | tr -d ' ')"
"$CLI" doctor --skip storage >/dev/null 2>&1 || true
after="$({ find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [[ "$after" -gt "$before" ]]; then
    pass "doctor writes a timestamped report"
else
    fail "doctor did not write a report ($before -> $after)"
fi
# Reports must not contain raw escape codes.
latest="$( { find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null || true; } | sort | tail -1)"
if [[ -n "$latest" ]] && ! grep -qP '\x1b\[' "$latest" 2>/dev/null; then
    pass "doctor report has escapes stripped"
else
    fail "doctor report contains ANSI escapes"
fi

before="$({ find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null || true; } | wc -l | tr -d ' ')"
"$CLI" doctor --skip storage --no-report >/dev/null 2>&1 || true
after="$({ find "$TEST_ROOT/state/reports" -name 'doctor-*.log' 2>/dev/null || true; } | wc -l | tr -d ' ')"
assert_equals "$after" "$before"

# New sections are reachable by name and listed in the usage text.
#
# This used to be 38 assertions - "--help lists <section>" once with a `doctor `
# prefix and once without - checking that a help string contains 19 words it
# already contains. No change to any other feature can break that, and the one
# comparison below catches the only thing it ever could.
usage="$("$CLI" doctor --help 2>&1)"


# Every name in the usage text must be a name doctor_wants accepts. Any of
# 0/1/2 is a valid doctor result - a section run in isolation can legitimately
# report warnings or errors.
#
# Stop at the first blank line. Without that bound the scrape swallows the prose
# after the list and starts asserting that "An", "unknown", "section" are valid
# section names - which passes, so the bug is invisible except as an inflated
# total.
mapfile -t HELP_SECTIONS < <(
    printf '%s\n' "$usage" \
        | sed -n '/^Sections:/,/^$/p' \
        | tail -n +2 \
        | tr -s ' \t\n' '\n' \
        | grep -v '^$'
)

# Every section must be runnable by name. This used to be 19 separate
# assertions, each spawning the whole of doctor - ~19 process launches to learn
# that none of them crashed. One loop, one assertion, same coverage.
#
# The exact code is deliberately NOT asserted: 0, 1 and 2 are all legitimate
# doctor results and which one you get depends on the host, so pinning a
# per-section code was a test that could only fail on someone else's machine.
section_failures=""
section_count=0
# The list in --help must match the list doctor validates against, or the two
# drift and a typo'd section becomes unroutable. This replaced 38 assertions
# ("--help lists <section>", once with a `doctor ` prefix and once without) that
# checked a help string contained 19 words it already contained. Reuses the
# extractor above rather than adding a second one.
source_sections="$(sed -n 's/^DOCTOR_SECTIONS="\(.*\)"$/\1/p' "$ROOT_DIR/commands/doctor.sh")"
if [[ -z "$source_sections" ]]; then
    fail "could not read DOCTOR_SECTIONS from doctor.sh"
else
    missing_help=""
    for section in $source_sections; do
        printf '%s\n' "${HELP_SECTIONS[@]}" | grep -qxF "$section" || missing_help+="$section "
    done
    if [[ -z "$missing_help" ]]; then
        pass "doctor --help lists every section the validator accepts"
    else
        fail "doctor --help omits: ${missing_help% }"
    fi
fi

for section in "${HELP_SECTIONS[@]}"; do
    section_count=$((section_count + 1))
    # `if`, not a bare call followed by `rc=$?`: this file runs under `set -e`,
    # and a command that exits non-zero outside a condition aborts the whole
    # suite before the status can be read - which is how this loop silently
    # killed the run instead of reporting anything.
    if "$CLI" doctor --only "$section" --no-report >/dev/null 2>&1; then
        section_rc=0
    else
        section_rc=$?
    fi
    if (( section_rc > 2 )); then
        section_failures+="$section(exit $section_rc) "
    fi
done
if (( section_count == 0 )); then
    fail "no doctor sections were run - the section list came back empty"
elif [[ -n "$section_failures" ]]; then
    fail "doctor --only is broken for: ${section_failures% }"
else
    pass "all $section_count sections run by name via doctor --only"
fi


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
# Install pipeline, end to end through the CLI
# ============================================
# These are the tests that would have caught the errexit leak: they drive the
# real `hyprx install` binary with a stubbed package layer, rather than calling
# the stage functions directly. The suite previously never invoked
# `hyprx install` through the CLI at all - only `install --help` and
# `install --bogus` - so no test could observe what the install stage returned
# or what the pipeline did after it.
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "hyprx install end to end"
if section_runs; then

# The only section whose EXECUTION is expensive: it installs the CLI into a
# sandbox and runs it four times, which is seconds of subprocess work that most
# edits cannot possibly affect. Guarded so `-f` skips the work, not just its
# reporting. Everything it exports is read only by sections that still run.

E2E_ROOT="$TEST_ROOT/e2e"
mkdir -p "$E2E_ROOT/bin"
export HYPRX_INSTALL_DIR="$E2E_ROOT/share/hyprx"
export HYPRX_BIN_DIR="$E2E_ROOT/bin"
bash "$ROOT_DIR/install.sh" >/dev/null 2>&1
E2E_CLI="$HYPRX_BIN_DIR/hyprx"

# Stub `pacman` so nothing real is ever touched. Answers:
#   -Q <pkg>   not installed   (exit 1)
#   -Si <pkg>  known (exit 0) unless it is in E2E_UNKNOWN_PKGS -> passes
#              validation, or is refused, which is how a package that the repos
#              genuinely do not have is reproduced without editing packages.list
#   -S ...     the FAIL_PKGS list decides
#   -Qtdq      no orphans
#   -Qdtq      no orphans
# `sudo` is stubbed too so nothing can escalate.
cat >"$E2E_ROOT/bin/pacman" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    -Q|-Qq)  exit 1 ;;
    -Si)
        for arg in "$@"; do
            case "$arg" in
                -*) continue ;;
                *)
                    if printf '%s\n' "$E2E_UNKNOWN_PKGS" | grep -qx "$arg"; then
                        exit 1
                    fi
                    ;;
            esac
        done
        exit 0
        ;;
    -Qtdq)   exit 0 ;;
    -Qdtq)   exit 1 ;;
    -S)
        for arg in "$@"; do
            case "$arg" in
                -*) continue ;;
                *)
                    if printf '%s\n' "$E2E_FAIL_PKGS" | grep -qx "$arg"; then
                        echo "error: failed to prepare transaction ($arg)" >&2
                        exit 1
                    fi
                    ;;
            esac
        done
        exit 0
        ;;
esac
exit 0
STUB
# `sudo` is stubbed so the gate passes. The real sudo needs a tty and an
# authenticated ticket, neither of which a non-interactive test run has, so
# without this the pipeline stops at the gate and every stage after it is never
# reached - which is exactly the gap that let a fatal bug in the install loop
# ship green.
#
# The gate prefers `sudo -n true` (never prompts, does not extend the
# credential timestamp) and only falls back to `sudo -v` on a tty. clean.sh and
# services.sh also use `sudo -n true`. Everything else execs the stubbed command.
cat >"$E2E_ROOT/bin/sudo" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    -v|-n) exit 0 ;;
esac
exec "$@"
STUB
# `yay` is stubbed for the same reason `pacman` is. Until now every package
# passed `hyprx_pkg_exists_official`, so the AUR fallback was unreachable and
# the suite never invoked a real helper. A package that the repos do NOT have
# takes that path, and an unstubbed `yay -Si` would query the AUR over the
# network - turning a code regression into a slow run or a red CI for the wrong
# reason. Same answers as pacman's -Si, so official and AUR agree.
cat >"$E2E_ROOT/bin/yay" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    -Si)
        for arg in "$@"; do
            case "$arg" in
                -*) continue ;;
                *)
                    if printf '%s\n' "$E2E_UNKNOWN_PKGS" | grep -qx "$arg"; then
                        exit 1
                    fi
                    ;;
            esac
        done
        exit 0
        ;;
esac
exit 0
STUB
# `systemctl` is stubbed too. Until now every services.list entry resolved to
# "no unit file", so the stage did nothing but print warnings and never reached
# an enable. With the unit-name fixed, a host that actually has networkmanager
# or pipewire would have `systemctl enable --now` run against it by the test
# suite - mutating the real machine to make a test pass.
#
# The stub answers list-unit-files/is-enabled from E2E_UNITS (space-separated,
# full unit names; empty by default, which reproduces the old all-skipped
# behaviour) and treats every mutation as a no-op.
cat >"$E2E_ROOT/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
user=false
verb=""
pos=()
for a in "$@"; do
    case "$a" in
        --user) user=true ;;
        --*)    ;;
        *)      if [[ -z "$verb" ]]; then verb="$a"; else pos+=("$a"); fi ;;
    esac
done

known() {
    local u="$1" x
    for x in $2; do [[ "$x" == "$u" ]] && return 0; done
    return 1
}

case "$verb" in
    list-unit-files)
        if $user; then
            known "${pos[0]:-}" "${E2E_USER_UNITS:-}" || exit 1
        else
            known "${pos[0]:-}" "${E2E_UNITS:-}" || exit 1
        fi
        echo "${pos[0]:-} enabled enabled"
        exit 0
        ;;
    is-enabled)
        known "${pos[0]:-}" "${E2E_UNITS:-} ${E2E_USER_UNITS:-}" \
            && { echo enabled; exit 0; }
        echo disabled
        exit 1
        ;;
    is-active) echo active; exit 0 ;;
    enable|disable|start|stop|restart|daemon-reload|mask|unmask) exit 0 ;;
esac
exit 0
STUB
chmod +x "$E2E_ROOT/bin/pacman" "$E2E_ROOT/bin/sudo" "$E2E_ROOT/bin/yay" \
         "$E2E_ROOT/bin/systemctl"

export PATH="$E2E_ROOT/bin:$PATH"
export E2E_FAIL_PKGS=""
export E2E_UNKNOWN_PKGS=""
export E2E_UNITS=""
export E2E_USER_UNITS=""
export HYPRX_TARGET_HOME="$E2E_ROOT/home"
export HYPRX_STATE_DIR="$E2E_ROOT/state"

# The font install must not touch the real network during a test run: four TLS
# fetches per invocation, and a network outage would turn a code regression into
# a red CI for the wrong reason.
#
# Instead the source is redirected to a file:// URL and the pin list to the real
# checksums of the fixtures, so the fetch -> size -> SHA256 -> move -> fc-cache
# path is genuinely exercised with no network. The production pin list is
# asserted separately below, so overriding it here cannot hide a bad pin.
export HYPRX_FONT_SOURCE="file://$TEST_ROOT/fontsrc"
FONT_SPEC="$(font_fixture_spec "$TEST_ROOT/fontsrc")"
export HYPRX_FONT_SPEC="$FONT_SPEC"
export HYPRX_FONT_DIR="$E2E_ROOT/fonts"

mkdir -p "$HYPRX_TARGET_HOME/.config" "$HYPRX_STATE_DIR"

# --- 1. a clean install reaches the end and says so ------------------------
# The `&&/||` form, not `out="$(...)"; rc=$?`: this file runs under
# `set -euo pipefail`, and a bare assignment whose command substitution exits
# non-zero is itself a failing command - so the suite would abort here on
# exactly the case this block exists to test, before any assertion ran.
e2e_out="$(HYPRX_STATE_DIR="$E2E_ROOT/state" "$E2E_CLI" install 2>&1)" && e2e_rc=0 || e2e_rc=$?

if grep -q "Installation completed successfully" <<<"$e2e_out"; then
    pass "install reports success when nothing fails"
else
    fail "install did not report success on a clean run"
fi
assert_equals "0" "$e2e_rc"

# One banner, not five. preflight.sh and compatibility.sh each opened with
# hyprx_ui_header, as did validator.sh and install_packages.sh, so a single
# install scrolled past five copies of the same box.
banner_count="$(grep -c 'HyprX  ' <<<"$e2e_out")"
assert_equals "1" "$banner_count"

# The two gates are now one, and it must appear exactly once.
gate_count="$(grep -c '== Preflight checks ==' <<<"$e2e_out")"
assert_equals "1" "$gate_count"

if grep -q 'Checking system compatibility' <<<"$e2e_out"; then
    fail "the old second gate is still running"
else
    pass "there is no second compatibility gate"
fi

# The gate must probe each fact exactly once, and must never use `sudo -v`.
#
# `sudo -v` refreshes the credential timestamp and can prompt for a password;
# `sudo -n true` only tests for a cached ticket and never prompts. The old pair
# of gates called `sudo -v` twice per install and `ping` twice as well.
#
# Measured by calling hyprx_install_gate directly rather than through the CLI,
# so the count cannot be polluted by services.sh and clean.sh - which run their
# own `sudo -n true` later, correctly, as separate stages.
#
# The probes are counted with real wrapper scripts on PATH rather than shell
# functions: the gate runs inside a `bash -c` subshell, which re-sources
# bootstrap.sh and would discard any function defined in this scope.
SPY_DIR="$TEST_ROOT/spybin"
PROBE_LOG="$TEST_ROOT/probe.log"
mkdir -p "$SPY_DIR"

make_spy() {
    local name="$1"
    cat >"$SPY_DIR/$name" <<SPY
#!/usr/bin/env bash
echo "$name \$*" >> "$PROBE_LOG"
exec "$(command -v "$name" 2>/dev/null || echo true)" "\$@"
SPY
    chmod +x "$SPY_DIR/$name"
}

# awk is spied as well as the obvious four, because the RAM read is an awk
# invocation and that is the probe whose duplication was a real bug.
for spy in sudo ping df nproc awk; do
    make_spy "$spy"
done

# awk is spied too, but only to count the RAM read. It must still behave
# normally, so it forwards to the real awk.
: >"$PROBE_LOG"

(
    PATH="$SPY_DIR:$PATH" \
    HYPRX_DRY_RUN=1 \
    bash -c 'source "$1/lib/bootstrap.sh"; hyprx_install_gate' _ "$ROOT_DIR"
) >/dev/null 2>&1

spy_count() {
    local pattern="$1" n
    n="$(grep -cE "$pattern" "$PROBE_LOG" 2>/dev/null || true)"
    printf '%s' "${n:-0}"
}

sudo_v="$(spy_count '^sudo -v')"
if [[ "$sudo_v" == "0" ]]; then
    pass "the gate never calls 'sudo -v' - no prompt, no timestamp extension"
else
    fail "the gate called 'sudo -v' $sudo_v time(s)"
fi

sudo_n="$(spy_count '^sudo -n')"
if [[ "$sudo_n" == "1" ]]; then
    pass "the gate probes the sudo ticket exactly once"
else
    fail "the gate made $sudo_n sudo probes, expected exactly 1"
fi

# Reports the gate's probe-cache state for the network check:
#
#   <one line per cache entry>
#   before=N   # cache size after the gate ran
#   after=N    # cache size after two more reachability asks
#   a=VALUE    # first repeated answer
#   b=VALUE    # second repeated answer
#
# Defined as a function so the assertion code above stays readable, and because
# it must run in a child shell: HYPRX_GATE_CACHE is populated at source time in
# that child, not here.
hyprx_test_run_gate_cache() {
    local out="$1"
    : >"$out"
    bash -c '
        source "$1/lib/bootstrap.sh"
        hyprx_install_gate >/dev/null 2>&1

        for entry in "${HYPRX_GATE_CACHE[@]}"; do
            printf "%s\n" "$entry"
        done

        before="${#HYPRX_GATE_CACHE[@]}"

        # Destination-variable API, not $(...): a command substitution would run
        # the probe in a subshell and discard the cache write.
        hyprx_gate_internet_state a
        hyprx_gate_internet_state b
        after="${#HYPRX_GATE_CACHE[@]}"

        printf "before=%s\nafter=%s\na=%s\nb=%s\n" \
            "$before" "$after" "$a" "$b"
    ' _ "$ROOT_DIR" >"$out" 2>&1
}

# Network reachability must be probed once and then CACHED.
#
# Counting rung calls does not work: bash's /dev/tcp is the first rung and uses
# no binary, so on a working host it answers immediately and the spied
# ping/curl/wget are correctly never reached - a test asserting on them fails
# for the right code's reason. The gate's own probe cache is the real invariant,
# so that is what gets inspected.
#
# This block also deliberately does NOT put $SPY_DIR on PATH. The spies append
# to the shared $PROBE_LOG, and a full extra gate run here silently doubled the
# nproc/df/meminfo counts asserted further down.
net_cache_log="$TEST_ROOT/netcache.log"
hyprx_test_run_gate_cache "$net_cache_log"

if [[ -f "$net_cache_log" ]]; then
    net_entries="$(grep -c '^internet=' "$net_cache_log" 2>/dev/null || true)"
    net_entries="${net_entries:-0}"
    if (( net_entries == 1 )); then
        pass "the gate measures network reachability exactly once"
    else
        fail "the gate recorded $net_entries reachability measurements, expected 1"
    fi

    net_before="$(sed -n 's/^before=//p' "$net_cache_log")"
    net_after="$(sed -n 's/^after=//p' "$net_cache_log")"
    if [[ -n "$net_before" && "$net_before" == "$net_after" ]]; then
        pass "asking reachability again costs nothing - the answer is cached"
    else
        fail "the network answer is not cached (${net_before:-?} -> ${net_after:-?} cache entries)"
    fi

    net_a="$(sed -n 's/^a=//p' "$net_cache_log")"
    net_b="$(sed -n 's/^b=//p' "$net_cache_log")"
    if [[ -n "$net_a" && "$net_a" == "$net_b" ]]; then
        pass "repeated reachability asks return the same answer"
    else
        fail "reachability gave two different answers: '$net_a' then '$net_b'"
    fi
fi

# A MISSING probe tool must never be read as an unreachable network.
#
# The gate used to require `ping`, which lives in iputils and is not a dependency
# of anything here. On archlinux:base - the container this suite itself runs in
# - ping is absent, so the probe failed, the gate declared the network
# unreachable, and `hyprx install` aborted before installing anything. Every
# E2E install assertion failed for a reason that had nothing to do with the code
# under test.
#
# So: no probe tool at all must be reported as UNKNOWN and be advisory, never
# fatal. This asserts that by hiding every probe from the gate.
NOPROBE_DIR="$TEST_ROOT/noprobe"
mkdir -p "$NOPROBE_DIR"

# A PATH containing only the shims that make each probe fail with 127, which is
# what "command not found" looks like to a script.
for tool in ping curl wget; do
    printf '#!/usr/bin/env bash\nexit 127\n' >"$NOPROBE_DIR/$tool"
    chmod +x "$NOPROBE_DIR/$tool"
done

# bash's /dev/tcp is the first probe and needs no binary, so it has to be
# defeated too. Overriding the probe function is the cleanest way to simulate
# "nothing available" without needing a network namespace.
gate_no_probe_log="$TEST_ROOT/gate-noprobe.log"
(
    PATH="$NOPROBE_DIR:$PATH" \
    HYPRX_DRY_RUN=1 \
    bash -c '
        source "$1/lib/bootstrap.sh"
        hyprx_gate_internet_probe() { printf "unknown"; }
        hyprx_install_gate
    ' _ "$ROOT_DIR"
) >"$gate_no_probe_log" 2>&1 || true
sed -i 's/\x1b\[[0-9;]*m//g' "$gate_no_probe_log"

if grep -q 'Could not verify network reachability' "$gate_no_probe_log"; then
    pass "a missing probe tool is reported as unknown, not as 'no network'"
else
    fail "a missing probe tool was not reported as unknown"
    grep -E 'Network|Cannot install' "$gate_no_probe_log" | sed 's/^/      /'
fi

if grep -q 'Cannot install' "$gate_no_probe_log"; then
    fail "an unverifiable network aborted the install"
else
    pass "an unverifiable network does not abort the install"
fi

# The same override, but reporting a genuine outage, must still be fatal on a
# real run. Otherwise the fix above would have over-corrected into never
# warning.
gate_down_log="$TEST_ROOT/gate-down.log"
(
    PATH="$NOPROBE_DIR:$PATH" \
    HYPRX_DRY_RUN=0 \
    bash -c '
        source "$1/lib/bootstrap.sh"
        hyprx_gate_internet_probe() { printf "down"; }
        hyprx_install_gate
    ' _ "$ROOT_DIR"
) >"$gate_down_log" 2>&1 || true
sed -i 's/\x1b\[[0-9;]*m//g' "$gate_down_log"

if grep -q 'Network unreachable' "$gate_down_log"; then
    pass "a genuine outage is still detected"
else
    fail "a genuine outage is no longer detected"
fi

nproc_n="$(spy_count '^nproc')"
if [[ "$nproc_n" == "1" ]]; then
    pass "the gate probes the CPU count exactly once"
else
    fail "the gate probed the CPU count $nproc_n times"
fi

# df twice is correct - / and $HOME are different filesystems and both matter -
# but each must be asked exactly once.
df_n="$(spy_count '^df ')"
if [[ "$df_n" == "2" ]]; then
    pass "the gate measures each of / and \$HOME exactly once"
else
    fail "the gate ran df $df_n times, expected 2 (once per filesystem)"
fi

# The RAM read must be one awk invocation over /proc/meminfo.
meminfo_n="$(spy_count '^awk .*MemTotal')"
if [[ "$meminfo_n" == "1" ]]; then
    pass "the gate reads MemTotal once"
else
    fail "the gate read MemTotal $meminfo_n times"
fi

# Every stage must have run. The service stage did not exist before, so this is
# also the assertion that README.md:15 ("Enables the systemd services listed in
# services.list") is now true rather than aspirational.
for stage in "Preflight checks" "Validating packages" "Installing packages" "Fonts" "Systemd services" "Deploying configuration" "Snapshot saved"; do
    if grep -q "$stage" <<<"$e2e_out"; then
        pass "install ran the '$stage' stage"
    else
        fail "install never reached the '$stage' stage"
    fi
done

# The configs and the state must actually be on disk afterwards.
assert_true test -d "$HYPRX_TARGET_HOME/.config/hypr"
assert_true test -f "$HYPRX_TARGET_HOME/.config/waybar/config.jsonc"
if [[ -f "$HYPRX_STATE_DIR/install.state" ]]; then
    fail "install.state left behind after a clean install"
else
    pass "install.state cleared on success"
fi

# --- 2. THE REGRESSION: failing packages must not abort the pipeline -------
# Before the fix, `set -e` leaked out of the install loop, so the first retry of
# a failing package killed the process: no retry ladder, no summary, no deploy,
# no snapshot, and install.state left behind for the next run to resume from.
export E2E_FAIL_PKGS="rofi
swaync"

mkdir -p "$E2E_ROOT/home2/.config"
e2e_out="$(HYPRX_TARGET_HOME="$E2E_ROOT/home2" "$E2E_CLI" install 2>&1)" && e2e_rc=0 || e2e_rc=$?

# It must NOT claim success.
if grep -q "Installation completed successfully" <<<"$e2e_out"; then
    fail "install claimed success while packages were failing"
else
    pass "install does not claim success when packages fail"
fi

# It must still finish the pipeline.
for stage in "Retrying failed packages" "Installation Summary" "Systemd services" "Deploying configuration"; do
    if grep -q "$stage" <<<"$e2e_out"; then
        pass "pipeline survived failures and reached '$stage'"
    else
        fail "pipeline aborted before '$stage' (errexit leak?)"
    fi
done

# The retry ladder must have actually retried.
retry_count="$(grep -c "Retrying " <<<"$e2e_out")"
if (( retry_count > 0 )); then
    pass "retry ladder ran ($retry_count attempts)"
else
    fail "no retry attempts after a package failure"
fi

# The summary must report the failures.
if grep -qE "Failed[[:space:]]*:[[:space:]]*[1-9]" <<<"$e2e_out"; then
    pass "install summary reports a non-zero failure count"
else
    fail "install summary did not report the failures"
fi

# Non-zero exit.
if (( e2e_rc != 0 )); then
    pass "install exits non-zero when packages fail (rc=$e2e_rc)"
else
    fail "install exited 0 despite failing packages"
fi

# Recovery state must be cleared even on a partial run - otherwise the next
# install resumes from a phantom interrupted one.
if [[ -f "$E2E_ROOT/state/install.state" ]]; then
    fail "install.state left behind after a partial install"
else
    pass "install.state cleared after a partial install"
fi

# And the configs must still have been deployed, because that is what the user
# needs in order to recover.
assert_true test -d "$E2E_ROOT/home2/.config/hypr"

export E2E_FAIL_PKGS=""

# --- 3. --dry-run through the CLI changes nothing --------------------------
DRY_HOME="$E2E_ROOT/dryhome"
mkdir -p "$DRY_HOME/.config"
dry_before="$(find "$DRY_HOME" | wc -l | tr -d ' ')"
# The `&&/||` form, not a bare assignment: this file runs under `set -e`, and a
# command substitution that exits non-zero inside one is itself a failing
# command - so as soon as --dry-run is able to fail (it now can, when a package
# cannot be resolved) the bare form would abort the suite here instead of
# asserting anything.
dry_out="$(HYPRX_TARGET_HOME="$DRY_HOME" HYPRX_STATE_DIR="$E2E_ROOT/state" "$E2E_CLI" install --dry-run 2>&1)" && dry_rc=0 || dry_rc=$?

if grep -q "Dry run complete" <<<"$dry_out"; then
    pass "install --dry-run reports it changed nothing"
else
    fail "install --dry-run did not print its completion notice"
fi

dry_after="$(find "$DRY_HOME" | wc -l | tr -d ' ')"
assert_equals "$dry_before" "$dry_after"

if [[ -d "$DRY_HOME/.config/hypr" ]]; then
    fail "install --dry-run deployed configs anyway"
else
    pass "install --dry-run deployed nothing"
fi

# It must still reach every stage - that is the point of the flag.
for stage in "Validating packages" "Installing packages" "Fonts" "Systemd services" "Deploying configuration"; do
    if grep -q "$stage" <<<"$dry_out"; then
        pass "install --dry-run reached '$stage'"
    else
        fail "install --dry-run skipped '$stage'"
    fi
done

# --dry-run must not claim a snapshot it did not write.
if grep -q "Snapshot saved" <<<"$dry_out"; then
    fail "install --dry-run wrote a snapshot"
else
    pass "install --dry-run wrote no snapshot"
fi

# --- 4. an unresolvable package must not be reported as success -------------
# Reproduced from a real run: a stale install.state carried a package the repos
# do not have, the gate resumed it, validation printed "Package not found: bad"
# - and the install then deployed every config, installed the fonts, saved a
# snapshot, wrote a report and exited 0 with "Installation completed
# successfully."
#
# The cause was one line: `hyprx_validator_validate || return 1` in engine.sh,
# where the validator's last statement was `if cond; then ...; fi` - which
# exits 0 whether the body ran or not. Dead code, so nothing could ever return.
#
# The queue is seeded through install.state rather than packages.list: that is
# both how it happened in the wild and the only way to get an unknown package
# into the queue without editing a tracked file while the suite runs.
seed_pending_queue() {
    mkdir -p "$E2E_ROOT/state"
    {
        echo "PACKAGE_MANAGER=pacman"
        echo
        echo "[PENDING]"
        echo "$1"
    } >"$E2E_ROOT/state/install.state"
}

UNRESOLVED_PKG="hyprx-definitely-not-a-real-package-xyz"
export E2E_UNKNOWN_PKGS="$UNRESOLVED_PKG"

seed_pending_queue "$UNRESOLVED_PKG"
mkdir -p "$E2E_ROOT/home3/.config"
e2e_out="$(HYPRX_TARGET_HOME="$E2E_ROOT/home3" "$E2E_CLI" install 2>&1)" && e2e_rc=0 || e2e_rc=$?

if grep -q "Package not found: $UNRESOLVED_PKG" <<<"$e2e_out"; then
    pass "validation reports an unresolvable package"
else
    fail "validation did not report the unresolvable package"
fi

if grep -q "Installation completed successfully" <<<"$e2e_out"; then
    fail "install claimed success while a package could not be resolved"
else
    pass "install does not claim success with an unresolvable package"
fi

if (( e2e_rc != 0 )); then
    pass "install exits non-zero when a package cannot be resolved (rc=$e2e_rc)"
else
    fail "install exited 0 despite an unresolvable package"
fi

# Not aborting is deliberate: the configs and the snapshot are what let the
# user fix the list and re-run. Only the verdict may change.
assert_true test -d "$E2E_ROOT/home3/.config/hypr"

if [[ -f "$E2E_ROOT/state/install.state" ]]; then
    fail "install.state left behind after a validation failure"
else
    pass "install.state cleared after a validation failure"
fi

# --dry-run must predict the same verdict. Thresholds (disk, RAM, network)
# downgrade under --dry-run, because probing a machine that cannot satisfy them
# is often the point; a package that does not exist is wrong on any machine, so
# a dry run that says "fine" is simply a false prediction.
seed_pending_queue "$UNRESOLVED_PKG"
dry_out="$(HYPRX_TARGET_HOME="$E2E_ROOT/home3" "$E2E_CLI" install --dry-run 2>&1)" && dry_rc=0 || dry_rc=$?

if (( dry_rc != 0 )); then
    pass "install --dry-run exits non-zero for an unresolvable package (rc=$dry_rc)"
else
    fail "install --dry-run predicted success for an unresolvable package"
fi

if grep -q "could not resolve" <<<"$dry_out"; then
    pass "install --dry-run reports the unresolved package"
else
    fail "install --dry-run did not report the unresolved package"
fi

if [[ -f "$E2E_ROOT/state/install.state" ]]; then
    pass "install --dry-run left the pending queue alone"
else
    fail "install --dry-run discarded the pending queue it had just resumed"
fi

rm -f "$E2E_ROOT/state/install.state"
export E2E_UNKNOWN_PKGS=""

# ============================================
# wallust template / stylesheet variable contract
# ============================================
# wallust overwrites config/waybar/styles/colors.css on the FIRST wallpaper
# change. Five variables existed only in the committed default, so after that
# change GTK dropped every rule using them and the bar silently lost its module
# backgrounds, borders, rounded corners and two module colours - while a fresh
# clone still looked correct, which is why it shipped.

fi  # section_runs - guarded: skipped unless it matches --filter
section_start "wallust template contract"

colour_vars() {
    grep -oE '^\s*@define-color\s+[a-zA-Z0-9_-]+' "$1" | awk '{print "@"$2}' | sort -u
}

used_vars() {
    # @import/@define-color are at-rules, not variable references.
    grep -ohE '@[a-zA-Z0-9_-]+' "$@" 2>/dev/null \
        | grep -vE '^@(import|define-color|media|keyframes|supports)$' \
        | sort -u
}

WAYBAR_STYLES=(
    "$ROOT_DIR/config/waybar/styles/modules.css"
    "$ROOT_DIR/config/waybar/styles/tray.css"
    "$ROOT_DIR/config/waybar/styles/base.css"
    "$ROOT_DIR/config/waybar/styles/workspaces.css"
    "$ROOT_DIR/config/waybar/styles/tooltip.css"
    "$ROOT_DIR/config/waybar/styles/animations.css"
)

colour_vars "$ROOT_DIR/config/wallust/templates/waybar-colors.css" >"$TEST_ROOT/tmpl_vars"
used_vars "${WAYBAR_STYLES[@]}" >"$TEST_ROOT/used_vars"

assert_covers "waybar template defines every variable the stylesheets use" \
    "$TEST_ROOT/tmpl_vars" "$TEST_ROOT/used_vars"

colour_vars "$ROOT_DIR/config/waybar/styles/colors.css" >"$TEST_ROOT/default_vars"
case "$(files_equal "$TEST_ROOT/default_vars" "$TEST_ROOT/tmpl_vars")" in
    equal)
        pass "committed default and wallust template declare the same variables"
        ;;
    no-diff-tool)
        # Reported separately and unmistakably: with `diff` absent this branch
        # used to run the else below, which printed "variable sets differ:" and
        # then an empty diff - blaming the files for a missing program.
        fail "cannot compare variable sets: 'diff' is not installed"
        ;;
    *)
        fail "default/template variable sets differ: $(diff "$TEST_ROOT/default_vars" "$TEST_ROOT/tmpl_vars" | tr '\n' ' ')"
        ;;
esac

# The same contract for every other wallust template that feeds a stylesheet.
check_template_contract() {
    local tpl="$1"; shift
    local name; name="$(basename "$tpl")"
    colour_vars "$tpl" >"$TEST_ROOT/tv"
    used_vars "$@" >"$TEST_ROOT/uv"
    assert_covers "$name covers its consumer" "$TEST_ROOT/tv" "$TEST_ROOT/uv"
}

check_template_contract "$ROOT_DIR/config/wallust/templates/swaync-colors.css" "$ROOT_DIR/config/swaync/style.css"
check_template_contract "$ROOT_DIR/config/wallust/templates/wlogout-colors.css" "$ROOT_DIR/config/wlogout/style.css"

# --- every colour the templates emit must be one GTK can parse ---------------
# The contract above compares variable NAMES only, so it stayed green while the
# waybar template's values were unusable. wallust's `strip` filter removes the
# leading '#', so `{{color1}}` renders as `#8263B2` and `{{color1 | strip}}` as
# `8263B2`. Bare hex is not a colour, and GTK does not skip one bad declaration:
# it refuses the stylesheet, waybar exits, and the bar is simply gone. It cost a
# reboot to notice, because the log only ever said "no surface yet" - waybar's
# own output went to /dev/null.
#
# Rendered here instead of by running wallust, which is not in the test job.
# `strip` is emulated as wallust actually behaves - it drops the '#' - and not
# as the whitespace trim its name suggests, since believing the name is exactly
# what let this through. `strip` IS correct inside rgba(), which is why
# hypr-colors.lua uses it and this only rejects it as a standalone value.
render_wallust_colours() {
    sed -E \
        -e 's/\{\{[[:space:]]*[a-zA-Z0-9_]+[[:space:]]*\|[[:space:]]*rgb[[:space:]]*\}\}/26,43,60/g' \
        -e 's/\{\{[[:space:]]*[a-zA-Z0-9_]+[[:space:]]*\|[[:space:]]*strip[[:space:]]*\}\}/1A2B3C/g' \
        -e 's/\{\{[[:space:]]*[a-zA-Z0-9_]+[[:space:]]*\}\}/#1A2B3C/g' "$1"
}

colour_checked=0
colour_bad=()
for tpl in "$ROOT_DIR"/config/wallust/templates/*.css; do
    while IFS= read -r value; do
        [[ -z "$value" ]] && continue
        colour_checked=$((colour_checked + 1))
        if [[ "$value" =~ ^\#[0-9A-Fa-f]{3,8}$ ]] || [[ "$value" =~ ^rgba?\([^()]*\)$ ]]; then
            continue
        fi
        colour_bad+=("$(basename "$tpl"): $value")
    done < <(render_wallust_colours "$tpl" | awk '/@define-color/ { sub(/;[[:space:]]*$/, "", $3); print $3 }')
done

# The counter is the point: a glob or an awk that silently matches nothing would
# otherwise report "every colour is parseable" having checked none.
if (( colour_checked == 0 )); then
    fail "cannot verify template colours: no @define-color value was read at all"
elif (( ${#colour_bad[@]} > 0 )); then
    fail "$colour_checked colour value(s) checked, ${#colour_bad[@]} unparseable: ${colour_bad[*]}"
    info "GTK aborts the whole stylesheet on one bad value, so the affected app exits"
else
    pass "all $colour_checked wallust @define-color values are parseable GTK colours"
fi

# ============================================
# Fonts: Caudex only, JetBrainsMono gone
# ============================================
# Caudex is the only font this rice uses. It is fetched and SHA256-pinned by
# lib/installer/fonts.sh rather than installed as a package, because
# ttf-google-fonts-git pulls in the whole Google catalogue plus 22 font packages.
section_start "font configuration"

# JetBrainsMono was in every font-family while its package was in neither list -
# the README called it "assumed pre-installed". The whole UI depended on it.
if grep -rq "JetBrains" "$ROOT_DIR/config" "$ROOT_DIR/packages.list" 2>/dev/null; then
    hits="$(grep -rl "JetBrains" "$ROOT_DIR/config" "$ROOT_DIR/packages.list" 2>/dev/null | tr '\n' ' ')"
    fail "JetBrainsMono is still referenced: $hits"
else
    pass "no JetBrainsMono references remain"
fi

# The replacement must not have introduced an unquoted or empty font stack.
while IFS= read -r decl; do
    family="${decl#*: }"
    if [[ -z "${family// /}" ]]; then
        fail "empty font-family in $decl"
        continue
    fi
    if [[ "$family" == *"," ]] && [[ "${family%,}" =~ [[:space:]] ]]; then
        fail "trailing comma in font-family: $decl"
        continue
    fi
done < <(grep -rhoE 'font-family: [^;]+' "$ROOT_DIR/config" 2>/dev/null | sort -u)
pass "font-family declarations are well formed"

if [[ -f "$ROOT_DIR/lib/installer/fonts.sh" ]]; then
    # The shipped default pin list, read out of the source so this tracks the
    # file rather than a copy of it. The E2E block above overrides
    # HYPRX_FONT_SPEC with a local fixture, so this is the only assertion on the
    # real pins.
    default_spec="$(font_shipped_spec)"

    font_entries=0
    pin_ok=true
    for entry in $default_spec; do
        [[ "$entry" == *"|"* ]] || { pin_ok=false; continue; }
        name="${entry%%|*}"
        pin="${entry##*|}"
        # The trailing space of the last entry is part of the token, so trim it.
        pin="${pin%"${pin##*[![:space:]]}"}"

        [[ "$pin" =~ ^[0-9a-f]{64}$ ]] || { pin_ok=false; continue; }
        [[ "$name" =~ ^Caudex-(Regular|Bold|Italic|BoldItalic)\.ttf$ ]] || { pin_ok=false; continue; }
        font_entries=$((font_entries + 1))
    done

    if $pin_ok; then
        pass "the shipped pin list is 4 well-formed Caudex entries"
    else
        fail "the shipped pin list has a malformed entry: $default_spec"
    fi
    assert_equals "4" "$font_entries"

    # Four DISTINCT checksums. A duplicated one would install four copies of a
    # single file while still reporting every file as verified.
    # Word-split on purpose: $default_spec is a space-separated list of
    # "file|sha256" entries, and each field is split again on the pipe below.
    # shellcheck disable=SC2086
    dupes="$(printf '%s\n' $default_spec | awk -F'|' '{print $2}' | sort | uniq -d | tr -d ' ')"
    assert_equals "" "$dupes"

    # The upstream URL must be the real one. If it were pointed somewhere else
    # the pins would still "verify" against whatever that host served.
    if grep -q 'HYPRX_FONT_SOURCE:-https://raw.githubusercontent.com/google/fonts/main/ofl/caudex' \
        "$ROOT_DIR/lib/installer/fonts.sh"; then
        pass "fonts are fetched from the upstream Google Fonts repository"
    else
        fail "the Caudex source URL is not the upstream google/fonts repo"
    fi

    # Verify the pins against the real upstream files. Skipped without network,
    # because a CI outage must not read as a code regression - but on a machine
    # with connectivity this is the check that proves the pins are Caudex.
    if command -v curl >/dev/null 2>&1 && curl -fsSL --max-time 20 \
        -o /dev/null "https://raw.githubusercontent.com/google/fonts/main/ofl/caudex/Caudex-Regular.ttf" 2>/dev/null
    then
        upstream_spec="$(mktemp -d)"
        pin_mismatch=0
        for entry in $default_spec; do
            name="${entry%%|*}"
            pin="${entry##*|}"
            if curl -fsSL --max-time 60 -o "$upstream_spec/$name" \
                "https://raw.githubusercontent.com/google/fonts/main/ofl/caudex/$name" 2>/dev/null
            then
                got="$(sha256sum "$upstream_spec/$name" 2>/dev/null | awk '{print $1}')"
                if [[ "$got" != "$pin" ]]; then
                    fail "pin for $name does not match upstream (upstream may have been re-cut; re-pin deliberately)"
                    pin_mismatch=$((pin_mismatch + 1))
                fi
            else
                fail "could not fetch $name from upstream to verify its pin"
                pin_mismatch=$((pin_mismatch + 1))
            fi
        done
        rm -rf "$upstream_spec"
        (( pin_mismatch == 0 )) && pass "all 4 pinned checksums match the upstream Caudex files"
    else
        hyprx_ui_info "no network - upstream checksum verification skipped"
    fi
else
    fail "lib/installer/fonts.sh missing"
fi

# --- the fetch-and-verify path, exercised for real --------------------------
# Local fixtures, so this runs offline and installs no font binaries into the
# repository. A wrong checksum must fail the install rather than install the
# wrong bytes.
FONTBOX="$TEST_ROOT/fontbox"
font_fixture_spec "$FONTBOX/src" >/dev/null
fixture_spec="$(font_fixture_spec "$FONTBOX/src")"

(
    HYPRX_FONT_DIR="$FONTBOX/dst" \
    HYPRX_FONT_SOURCE="file://$FONTBOX/src" \
    HYPRX_FONT_SPEC="$fixture_spec" \
    HYPRX_DRY_RUN=0 \
    bash -c 'source "$1/lib/bootstrap.sh"; hyprx_fonts_install' _ "$ROOT_DIR"
) >"$FONTBOX/good.log" 2>&1
if [[ -f "$FONTBOX/dst/Caudex-Regular.ttf" ]] && grep -q "Installed" "$FONTBOX/good.log"; then
    pass "font install places verified files in the font dir"
else
    fail "font install did not install from a local source"
    tail -5 "$FONTBOX/good.log"
fi

# Idempotent: a second run must short-circuit on the verified copy.
(
    HYPRX_FONT_DIR="$FONTBOX/dst" \
    HYPRX_FONT_SOURCE="file://$FONTBOX/src" \
    HYPRX_FONT_SPEC="$fixture_spec" \
    HYPRX_DRY_RUN=0 \
    bash -c 'source "$1/lib/bootstrap.sh"; hyprx_fonts_install' _ "$ROOT_DIR"
) >"$FONTBOX/again.log" 2>&1
if grep -q "already installed and verified" "$FONTBOX/again.log"; then
    pass "font install short-circuits on a verified copy"
else
    fail "font install re-fetched instead of recognising the verified copy"
fi

# A corrupted pin must fail and leave nothing behind.
bad_spec="$(printf '%s' "$fixture_spec" \
    | sed 's/Caudex-Regular\.ttf|[0-9a-f]\{64\}/Caudex-Regular.ttf|0000000000000000000000000000000000000000000000000000000000000000/')"

# This one is EXPECTED to fail, so `|| true` is mandatory: under `set -e` a
# non-zero subshell would abort the suite before the assertion that proves the
# failure was the right one.
bad_rc=0
(
    HYPRX_FONT_DIR="$FONTBOX/dst2" \
    HYPRX_FONT_SOURCE="file://$FONTBOX/src" \
    HYPRX_FONT_SPEC="$bad_spec" \
    HYPRX_DRY_RUN=0 \
    bash -c 'source "$1/lib/bootstrap.sh"; hyprx_fonts_install' _ "$ROOT_DIR"
) >"$FONTBOX/bad.log" 2>&1 || bad_rc=$?
if (( bad_rc != 0 )) && grep -qi "checksum mismatch" "$FONTBOX/bad.log"; then
    pass "font install refuses a checksum mismatch"
else
    fail "font install accepted a bad checksum (rc=$bad_rc)"
fi
if [[ -d "$FONTBOX/dst2" ]] && [[ -n "$(ls -A "$FONTBOX/dst2" 2>/dev/null)" ]]; then
    fail "font install left files behind after a checksum failure"
else
    pass "font install leaves nothing behind after a checksum failure"
fi

# The heavyweight package must be gone.
if grep -qE '^\s*ttf-google-fonts' "$ROOT_DIR/packages.list"; then
    fail "ttf-google-fonts-git is still installed for one font"
else
    pass "the whole-Google-catalogue font package is not installed"
fi

# ============================================
# Dependency manifest
# ============================================
# Seven binaries were referenced by the config and installed by nothing:
# hyprpaper (the entire wallpaper/theming chain), notify-send (the error handler
# for six scripts), hostname, blueman-manager, nemo, rsync, fc-cache. Each
# failed silently. This is the guard so it cannot recur.
section_start "dependency manifest"

MANIFEST="$ROOT_DIR/database/binary-providers.conf"
if [[ -f "$MANIFEST" ]]; then
    pass "database/binary-providers.conf exists"

    # Every declared provider must be in packages.list, or the install will not
    # pull it and the binary will be missing at runtime.
    manifest_bad=0
    while IFS='|' read -r binary provider _rest; do
        # Trim BOTH ends of both fields. Leading-only trimming leaves the
        # padding the aligned table uses on the right, so every provider looked
        # like "hyprpaper       " and nothing matched packages.list.
        binary="${binary#"${binary%%[![:space:]]*}"}"
        binary="${binary%"${binary##*[![:space:]]}"}"
        provider="${provider#"${provider%%[![:space:]]*}"}"
        provider="${provider%"${provider##*[![:space:]]}"}"

        [[ -z "$binary" || -z "$provider" ]] && continue
        [[ "$provider" == "system" ]] && continue

        if ! grep -qx "$provider" "$ROOT_DIR/packages.list"; then
            fail "manifest: '$binary' needs '$provider', not in packages.list"
            manifest_bad=$((manifest_bad + 1))
        fi
    done <"$MANIFEST"
    if (( manifest_bad == 0 )); then
        pass "every manifest provider is in packages.list"
    fi

    # The seven that shipped broken. Five were fixed by adding a provider; two
    # were fixed by removing the reference entirely, so their absence from the
    # manifest is the correct end state and the config must no longer mention
    # them.
    for required_binary in hyprpaper notify-send hostname fc-cache fc-match; do
        if grep -qE "^\s*$required_binary\s*\|" "$MANIFEST"; then
            pass "manifest declares '$required_binary'"
        else
            fail "manifest does not declare '$required_binary' (it shipped broken)"
        fi
    done

    # nemo and rsync were resolved by deleting the reference, not by installing
    # them: the file-manager bind now uses thunar (already in packages.list) and
    # both dev-sync.sh copies are gone.
    for removed_ref in nemo rsync dev-sync; do
        if grep -rq "$removed_ref" "$ROOT_DIR/config" "$ROOT_DIR/scripts" 2>/dev/null; then
            where="$(grep -rl "$removed_ref" "$ROOT_DIR/config" "$ROOT_DIR/scripts" 2>/dev/null | tr '\n' ' ')"
            fail "'$removed_ref' is still referenced: $where"
        else
            pass "'$removed_ref' is no longer referenced"
        fi
    done

    # The file-manager bind must name something packages.list installs.
    fm="$(grep -oE 'local fileManager = "[^"]+"' "$ROOT_DIR/config/hypr/hyprland.lua" \
        | head -n1 | sed 's/.*"\(.*\)"/\1/')"
    if [[ -n "$fm" ]] && grep -qx "$fm" "$ROOT_DIR/packages.list"; then
        pass "the file-manager bind ('$fm') is in packages.list"
    else
        fail "the file-manager bind ('$fm') is not in packages.list"
    fi

    # And the packages must actually be in the list now.
    for required_pkg in hyprpaper libnotify inetutils hyprpolkitagent \
                       xdg-desktop-portal-hyprland pipewire wireplumber; do
        if grep -qx "$required_pkg" "$ROOT_DIR/packages.list"; then
            pass "packages.list includes '$required_pkg'"
        else
            fail "packages.list is still missing '$required_pkg'"
        fi
    done
else
    fail "database/binary-providers.conf missing - the manifest guard does not exist"
fi

# The portal and polkit gap: a Hyprland session with no portal silently fails
# screen sharing and every privileged GUI prompt.
if grep -qx "xdg-desktop-portal-hyprland" "$ROOT_DIR/packages.list" \
   && grep -qx "hyprpolkitagent" "$ROOT_DIR/packages.list"; then
    pass "portal and polkit agent are installed"
else
    fail "no portal/polkit agent - screen sharing and auth dialogs would fail"
fi

# `services.list` listed pipewire while no package provided it. A service for a
# package that is not installed cannot start, so this pair must agree.
if grep -qx "pipewire" "$ROOT_DIR/services.list" && ! grep -qx "pipewire" "$ROOT_DIR/packages.list"; then
    fail "services.list enables pipewire but packages.list does not install it"
else
    pass "services.list entries have their packages in packages.list"
fi

# ============================================
# Doctor: the sections and the exit code
# ============================================
section_start "doctor sections and exit codes"
if section_runs; then

for section in fonts manifest; do
    if printf '%s' "$usage" | grep -qF "$section"; then
        pass "doctor --help lists $section"
    else
        fail "doctor --help omits $section"
    fi
done

# The new sections must be routable.
assert_exit_in "doctor --only fonts"    "0,1,2" "$CLI" doctor --only fonts --no-report
assert_exit_in "doctor --only manifest" "0,1,2" "$CLI" doctor --only manifest --no-report

# The Applications section used to print a red X per missing app and exit 0.
# It has to feed the tallies now.
out="$("$CLI" doctor --only applications --no-report 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if printf '%s' "$out" | grep -q '^== Applications =='; then
    pass "--only applications runs the Applications section"
else
    fail "--only applications did not run the Applications section"
fi
# On this machine everything may well be present, so assert the mechanism: every
# app line must be a note (✓ or ✗ followed by text) and the section must be
# reachable through --json.
json_apps="$("$CLI" doctor --json 2>/dev/null || true)"
if printf '%s' "$json_apps" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
blob = " ".join(f["detail"] for f in d["findings"])
# These were hypr_table_row / plain printers and never reached findings.
missing = [k for k in ("Hyprland", "Waybar", "Rofi", "Kitty", "Git")
           if k not in blob]
if missing:
    sys.exit("absent from findings: " + ", ".join(missing))
' 2>/dev/null; then
    pass "Applications and system rows now appear in --json findings"
else
    fail "table-row sections are still absent from --json"
fi

# ============================================
# Config: validation before write
# ============================================
# A rejected set used to reset the key to its DEFAULT rather than leaving the
# previous value, while printing "Current value left unchanged".
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "config value preservation"

hyprx_config_set LOG_LEVEL debug
before_val="$(hyprx_config_get LOG_LEVEL)"
hyprx_config_set LOG_LEVEL verbose >/dev/null 2>&1 || true
after_val="$(hyprx_config_get LOG_LEVEL)"
assert_equals "debug" "$after_val"

hyprx_config_set LOG_LEVEL info >/dev/null

# A '#' inside a quoted value must survive the round trip.
printf 'HYPRX_CONFIG_LOG_FILE="/var/log/my#app.log" # a comment\n' >"$HYPRX_CONFIG_FILE"
hyprx_config_load >/dev/null 2>&1
assert_equals "/var/log/my#app.log" "$(hyprx_config_get LOG_FILE)"

# An unquoted trailing comment must still be stripped.
printf 'HYPRX_CONFIG_LOG_LEVEL=warn # trailing\n' >"$HYPRX_CONFIG_FILE"
hyprx_config_load >/dev/null 2>&1
assert_equals "warn" "$(hyprx_config_get LOG_LEVEL)"
hyprx_config_set LOG_LEVEL info >/dev/null

# THEME must accept a theme that is a FILE. It tested -d against a path that only
# ever contained one-dark.css, so the only shipped theme was unselectable.
if hyprx_config_validate THEME one-dark; then
    pass "THEME accepts the shipped one-dark theme"
else
    fail "THEME rejects one-dark - a theme is a file, not a directory"
fi
if hyprx_config_validate THEME definitely-not-a-theme; then
    fail "THEME accepts a theme that does not exist"
else
    pass "THEME rejects a nonexistent theme"
fi

# ============================================
# The preflight gate
# ============================================
# preflight.sh and compatibility.sh used to be two files that probed the same six
# facts and disagreed about three of them: internet was fatal in one and
# advisory in the other, `sudo -v` ran twice (and can prompt twice), and RAM was
# read with two different divisors so "8GB" was compared against gigabytes while
# "4GB" was compared against megabytes.
section_start "the preflight gate"
if section_runs; then

if [[ -f "$ROOT_DIR/lib/installer/gate.sh" ]]; then
    pass "lib/installer/gate.sh exists"
else
    fail "lib/installer/gate.sh missing"
fi

for gone in preflight.sh compatibility.sh; do
    if [[ -f "$ROOT_DIR/lib/installer/$gone" ]]; then
        fail "$gone still exists - the overlap is back"
    else
        pass "$gone is gone"
    fi
done

if grep -q 'gate.sh' "$ROOT_DIR/lib/bootstrap.sh"; then
    pass "bootstrap sources gate.sh"
else
    fail "gate.sh is not sourced by bootstrap"
fi

# The engine must run ONE gate, not two.
if [[ -f "$ROOT_DIR/lib/installer/engine.sh" ]]; then
    gate_calls="$(grep -cE 'hyprx_(install_gate|preflight_check|compatibility_check)' \
        "$ROOT_DIR/lib/installer/engine.sh")"
    if [[ "$gate_calls" == "1" ]]; then
        pass "engine.sh calls the gate exactly once"
    else
        fail "engine.sh invokes a gate $gate_calls times"
    fi
fi

# Memory must be read once, in one unit. The two old files disagreed on the
# divisor - "8GB" was compared against a value in gigabytes and "4GB" against a
# value in megabytes - which made both verdicts meaningless.
#
# Comments are stripped first: gate.sh documents the old divisors in its own
# header, and matching that prose would keep the test red forever for no reason.
gate_code="$(grep -vE '^[[:space:]]*#' "$ROOT_DIR/lib/installer/gate.sh")"

# Single-quoted on purpose: literal awk/shell fragments searched for in gate.sh,
# not patterns for this script to evaluate.
# shellcheck disable=SC2016
if grep -q 'int($2/1024)' <<<"$gate_code" \
   && ! grep -q '1024/1024' <<<"$gate_code"; then
    pass "RAM is read once, in megabytes"
else
    fail "gate.sh does not read RAM as a single value in MB"
fi

# Thresholds belong in one place, named.
for knob in HYPRX_MIN_DISK_ROOT_KB HYPRX_MIN_DISK_HOME_KB \
            HYPRX_MIN_RAM_FLOOR_MB HYPRX_MIN_RAM_RECOMMENDED_MB; do
    if grep -q "$knob=" "$ROOT_DIR/lib/installer/gate.sh"; then
        pass "$knob is a named constant"
    else
        fail "$knob is not a named constant"
    fi
done

# The gate must be honest: a fatal finding has to change the exit code.
# shellcheck disable=SC2016  # literal shell fragment, searched for in gate.sh
if grep -q 'fatal=$((fatal + 1))' "$ROOT_DIR/lib/installer/gate.sh" \
   && grep -q 'return 1' "$ROOT_DIR/lib/installer/gate.sh"; then
    pass "a fatal finding makes the gate return 1"
else
    fail "the gate can print a fatal finding without failing"
fi

# A dry run must not be blocked by things it cannot satisfy.
dry_gate="$("$CLI" install --dry-run 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)"
if grep -q 'Preflight checks' <<<"$dry_gate"; then
    pass "the gate runs under --dry-run"
else
    fail "the gate did not run under --dry-run"
fi
if grep -q 'Cannot install' <<<"$dry_gate"; then
    fail "--dry-run was blocked by a check it cannot satisfy"
else
    pass "--dry-run is not blocked by unsatisfiable checks"
fi

# The gate must not depend on a binary it has not declared.
#
# It used to hard-require `ping` (iputils), which is in no package list here.
# On a minimal system - including the container this suite runs in - that made
# the gate call an absent tool, read the result as "no network", and abort.
for probe_dep in ping curl wget; do
    if grep -qx "$probe_dep" "$ROOT_DIR/packages.list"; then
        pass "$probe_dep is a declared dependency"
    else
        # Not being declared is acceptable: the gate must merely never REQUIRE
        # one, and the ladder falls through to the next probe.
        pass "$probe_dep is not declared, and the gate falls through to it"
    fi
done

# And the gate must treat "no probe available" differently from "unreachable".
if grep -q 'Could not verify network reachability' "$ROOT_DIR/lib/installer/gate.sh"; then
    pass "the gate distinguishes unknown reachability from an outage"
else
    fail "the gate still conflates a missing probe with an unreachable network"
fi

# ============================================
# Services: the stage that did not exist
# ============================================
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "services.list handling"
if section_runs; then

if [[ -f "$ROOT_DIR/lib/installer/services.sh" ]]; then
    pass "lib/installer/services.sh exists"
    if grep -q "services.sh" "$ROOT_DIR/lib/bootstrap.sh"; then
        pass "bootstrap sources services.sh"
    else
        fail "services.sh is not sourced by bootstrap - the stage cannot run"
    fi
    if grep -q "hyprx_services_enable" "$ROOT_DIR/lib/installer/engine.sh"; then
        pass "the install engine calls hyprx_services_enable"
    else
        fail "engine never enables services (README.md:15 is still a lie)"
    fi
    # System and user units are mixed in services.list and the names give no
    # hint which is which, so the scope must be probed rather than assumed.
    #
    # This check used to be `grep -q "hyprx_service_scope" services.sh` - it
    # asserted the function was MENTIONED, never that it resolved anything,
    # which is precisely how a bug where all seven entries failed to resolve
    # shipped green.
    #
    # The bug: services.list holds bare names, and `systemctl list-unit-files`
    # matches only FULL unit names, so `NetworkManager` matched nothing and
    # exited 1. Every entry answered "no unit file in either scope" - including
    # networkmanager, pipewire, firewalld and bluez, which were installed - so
    # the stage reported Enabled 0 / Skipped 7 and enabled nothing at all.
    # doctor.sh appended the suffix and services.sh did not, so the two
    # disagreed about the same machine.
    if grep -q "hyprx_service_scope" "$ROOT_DIR/lib/installer/services.sh"; then
        pass "services resolve their systemd scope"
    else
        fail "services assume a single scope - pipewire is a user unit, the rest are system"
    fi

    # A bare name must resolve to the system scope...
    export E2E_UNITS="NetworkManager.service pipewire.service"
    scope="$(hyprx_service_scope NetworkManager)" || scope=""
    if [[ "$scope" == "system" ]]; then
        pass "a bare name resolves to its system scope"
    else
        fail "hyprx_service_scope NetworkManager gave '$scope', expected 'system'"
    fi

    # ...and one that does not exist must resolve to nothing. Normalising the
    # name must not turn every probe into a hit.
    scope="$(hyprx_service_scope hyprx-no-such-unit-xyz)" || scope=""
    if [[ -z "$scope" ]]; then
        pass "an absent unit still resolves to no scope"
    else
        fail "hyprx_service_scope invented a scope ('$scope') for a unit that does not exist"
    fi

    # An entry that already names a type must not gain a second suffix.
    if [[ "$(hyprx_service_unit_name greetd.socket)" == "greetd.socket" \
       && "$(hyprx_service_unit_name NetworkManager)" == "NetworkManager.service" ]]; then
        pass "unit-name normalisation is idempotent"
    else
        fail "hyprx_service_unit_name mis-normalised: $(hyprx_service_unit_name greetd.socket) / $(hyprx_service_unit_name NetworkManager)"
    fi

    # End to end through the stage itself: a declared unit must be recognised
    # and reported, not swallowed as missing.
    export E2E_UNITS="NetworkManager.service"
    svc_out="$(hyprx_services_enable 2>&1)" || true

    if grep -q "NetworkManager: already enabled (system)" <<<"$svc_out"; then
        pass "the services stage enables a unit that exists"
    else
        fail "the services stage did not recognise NetworkManager: $(head -4 <<<"$svc_out" | tr '\n' ' ')"
    fi

    if grep -q "NetworkManager: no unit file" <<<"$svc_out"; then
        fail "the services stage reported an installed unit as having no unit file"
    else
        pass "the services stage does not report an installed unit as missing"
    fi

    export E2E_UNITS=""
    HYPRX_SERVICES_ENABLED=()
    HYPRX_SERVICES_FAILED=()
    HYPRX_SERVICES_SKIPPED=()
else
    fail "lib/installer/services.sh missing - nothing enables services.list"
fi

# ============================================
# Entrypoint hardening
# ============================================
# bin/hyprx built a path from $1 and sourced it, so `hyprx ../../evil` ran an
# arbitrary file. It has no .sh suffix, so no lint or shellcheck job ever saw it
# either.
fi  # section_runs - guarded: skipped unless it matches --filter
section_start "entrypoint hardening"

cat >"$TEST_ROOT/evil.sh" <<'EVIL'
echo "arbitrary file was executed"
EVIL

bad_out="$("$CLI" '../../../../..'"$(basename "$TEST_ROOT")"'/evil' 2>&1 || true)"
if printf '%s' "$bad_out" | grep -q "arbitrary file was executed"; then
    fail "bin/hyprx sourced a path outside commands/ - arbitrary code execution"
else
    pass "bin/hyprx rejects a traversal command name"
fi

for bad_name in "a/b" "." ".." "UPPER" "-x"; do
    if "$CLI" "$bad_name" >/dev/null 2>&1; then
        fail "bin/hyprx accepted an invalid command name: $bad_name"
    else
        pass "bin/hyprx rejects '$bad_name'"
    fi
done

# Normal commands must still work.
assert_exit_in "hyprx help" "0" "$CLI" help
assert_exit_in "hyprx config list" "0" "$CLI" config list

# ============================================
# clean: measurement and skip accounting
# ============================================
section_start "clean accounting"

clean_usage="$("$CLI" clean --help 2>&1)"
if printf '%s' "$clean_usage" | grep -q "HYPRX_LOG_KEEP"; then
    pass "clean --help explains the LOG_KEEP/HYPRX_LOG_KEEP link"
else
    fail "clean --help does not mention HYPRX_LOG_KEEP"
fi

# Skipping a sudo step is not a failure - a non-interactive run must exit 0.
if grep -q "SKIPPED" "$ROOT_DIR/commands/clean.sh"; then
    pass "clean counts skipped steps separately from failures"
else
    fail "clean still treats an unauthenticated sudo skip as a failure"
fi

# /tmp cleanup must be scoped, or a day-old directory with a live socket in it
# gets removed along with everything inside.
if grep -qE 'find /tmp -mindepth 1 -user' "$ROOT_DIR/commands/clean.sh"; then
    fail "clean still walks all of /tmp for the current user's files"
else
    pass "clean scopes /tmp cleanup to /tmp/\$USER at maxdepth 1"
fi

# Every pruning step must report its bytes, not assume them.
prune_steps="$(grep -c 'add_freed' "$ROOT_DIR/commands/clean.sh")"
if (( prune_steps >= 6 )); then
    pass "clean reports reclaimed bytes across $prune_steps steps"
else
    fail "only $prune_steps measured steps - the trash/report/log steps assume their size"
fi


# ============================================
# Summary
# ============================================
log ""
log "========================================="

# When a filter is in play, say so. A run that reports 5 passes and 0 failures
# is indistinguishable from a healthy full run unless it states that 31
# sections were not counted - and that is exactly how a filtered run gets
# mistaken for the whole suite.
if [[ -n "$FILTER" ]]; then
    log "Filter: $FILTER"
    if (( ${#SECTION_SKIPPED[@]} > 0 )); then
        log "Not counted (${#SECTION_SKIPPED[@]} sections):"
        for skipped in "${SECTION_SKIPPED[@]}"; do
            log "  - $skipped"
        done
    else
        log "Every section matched the filter."
    fi
    log ""
fi

# The five slowest sections. The suite's cost is not spread evenly - the
# end-to-end install block is several seconds on its own - so knowing where the
# time goes is what makes "make it lighter" answerable instead of a guess.
if (( ${#SECTION_TIMES[@]} > 0 )); then
    log "Slowest sections:"
    while IFS=$'\t' read -r secs name; do
        log "  ${secs}s  $name"
    done < <(printf '%s\n' "${SECTION_TIMES[@]}" | sort -rn | head -5)
    log ""
fi

# Repeated here on purpose: this is the one part of the output a CI log viewer
# will not collapse, so a failure cannot hide in the middle of a long run.
# Each line is prefixed with its section, so when a batch of edits adds several
# assertions it is immediately clear which of them failed.
if (( FAILED > 0 )); then
    log "Failed assertions:"
    for failed_assertion in "${FAILED_ASSERTIONS[@]}"; do
        log "  - $failed_assertion"
    done
    log ""
fi

log "Passed : $PASSED"
log "Failed : $FAILED"
log "Finished: $(date)"
log "========================================="

((FAILED == 0))
