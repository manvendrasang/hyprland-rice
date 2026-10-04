#!/usr/bin/env bash

# Executable form of REVIEW.md.
#
# The review recorded a set of claims with file:line references. Two problems
# with that: line numbers rot on the next commit, and a claim you cannot re-run
# is a claim you have to trust. This script turns the checkable ones into
# assertions you can run in a second.
#
#   bash tests/review-checks.sh          # check only, exit 1 on any finding
#   bash tests/review-checks.sh --fix    # apply the safe mechanical fixes
#
# Most of these are ALSO covered by tests/run_tests.sh, which is the real gate.
# The duplication is deliberate: review-checks.sh reports the *reason* for each
# finding in prose, so a failure here is self-explanatory, while run_tests.sh is
# terse by design.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX=false
[[ "${1:-}" == "--fix" ]] && FIX=true

FINDINGS=0
FIXED=0

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
green(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
info() { printf '\033[1;36m%s\033[0m\n' "$*"; }

finding() {
    FINDINGS=$((FINDINGS + 1))
    red "  ✗ $1"
    [[ -n "${2:-}" ]] && printf '      %s\n' "$2"
}

fixed() {
    FIXED=$((FIXED + 1))
    green "  ✓ $1 (fixed)"
}

ok() { green "  ✓ $1"; }

section() { printf '\n\033[1;34m== %s ==\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# Tool-aware comparisons
# ---------------------------------------------------------------------------
# This script had the same defect it now reports in others, twice over:
#
#   * `if diff -q a b` exits 127 when diff is absent, which is non-zero, so the
#     else branch fired and the script filed a finding against the CODE for a
#     missing program.
#   * `miss="$(comm -23 a b)"; [[ -z "$miss" ]]` passes when comm is absent,
#     because a command that cannot run produces no output. A real, missing
#     variable would have been reported as covered.
#
# Both are the gate's `ping` bug: absence of a tool is not evidence about the
# thing being checked. So each helper separates "could not verify" from the two
# genuine answers.
#
# check_covers <ok-label> <finding-label> <reason> <have-file> <want-file>
check_covers() {
    local ok_label="$1" find_label="$2" reason="$3" have="$4" want="$5"
    local miss rc=0
    miss="$(comm -23 "$want" "$have" 2>/dev/null)" || rc=$?
    if (( rc != 0 )); then
        finding "$find_label: cannot verify ('comm' exited $rc - tool missing?)" \
            "a tool problem, not a code problem; install coreutils before running this"
    elif [[ -z "$miss" ]]; then
        ok "$ok_label"
    else
        finding "$find_label: $(tr '\n' ' ' <<<"$miss")" "$reason"
    fi
}

# check_files_equal <ok-label> <finding-label> <reason> <a> <b>
#
# exit 1 is the only code that means "the files differ".
check_files_equal() {
    local ok_label="$1" find_label="$2" reason="$3" a="$4" b="$5"
    local rc=0
    diff -q "$a" "$b" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ok "$ok_label" ;;
        1) finding "$find_label" "$reason" ;;
        *) finding "$find_label: cannot verify ('diff' exited $rc - tool missing?)" \
               "a tool problem, not a code problem; install diffutils before running this" ;;
    esac
}

# broken_grep_patterns <file>
#
# Prints "line N: <pattern>" for every single-quoted grep PATTERN in <file>
# that fails to COMPILE under the flavor its own line specifies (-E -> ERE,
# -F -> fixed and therefore always compilable, default -> BRE).
#
# Why this matters more than it looks: a pattern that will not compile makes
# grep exit 2, and exit 2 is non-zero exactly like a genuine miss. So
#
#     if grep -q 'BROKEN' file; then finding ...; else ok ...; fi
#
# takes the else branch and reports OK forever, while printing a grep error to
# stderr that nobody reads. review-checks.sh shipped one: `\-d "\$\{...` in a
# BRE, where `\{` opens an interval expression, so "THEME validation accepts
# files" was green unconditionally - a check whose failure mode is a silent
# pass is worse than no check at all.
broken_grep_patterns() {
    local file="$1" lineno=0 line n pat rc
    local re_grep='(^|[[:space:] (])grep'
    local re_fixed="$re_grep"'[^|&;]*[[:space:]]-[a-zA-Z]*F'
    local re_ere="$re_grep"'[^|&;]*[[:space:]]-[a-zA-Z]*E'

    while IFS= read -r line; do
        lineno=$((lineno + 1))

        # Comments may quote a broken pattern on purpose to illustrate it, and
        # a pattern held in a variable has no quotes to extract.
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" == *grep* ]] || continue

        n="$(tr -cd "'" <<<"$line" | wc -c)"
        (( n >= 2 && n % 2 == 0 )) || continue

        pat="$(sed -n "s/^[^']*'\([^']*\)'.*/\1/p" <<<"$line")"
        [[ -n "$pat" ]] || continue

        if [[ "$line" =~ $re_fixed ]]; then
            continue
        elif [[ "$line" =~ $re_ere ]]; then
            printf '%s\n' x | grep -q -E -- "$pat" 2>/dev/null; rc=$?
        else
            printf '%s\n' x | grep -q -- "$pat" 2>/dev/null; rc=$?
        fi

        (( rc >= 2 )) && printf 'line %s: %s\n' "$lineno" "$pat"
    done <"$file"
}

# ---------------------------------------------------------------------------
# Sanity: what platform are we on?
# ---------------------------------------------------------------------------
section "Environment"

if command -v pacman >/dev/null 2>&1; then
    ok "Arch-family system (pacman present)"
    pacman_ok=true
else
    info "not an Arch system - package-database checks will be skipped"
    pacman_ok=false
fi

# ===========================================================================
# A. errexit leak
# ===========================================================================
# The single worst bug in the review. `set -e` leaked out of the install loop,
# so the first retry of a failing package killed the whole process: no retry
# ladder, no summary, no deploy, no snapshot, and a stale install.state that
# made the NEXT install resume from a phantom interruption.
section "A. errexit leak in the install loop"

leak_files=0
for f in "$ROOT_DIR"/lib/installer/*.sh "$ROOT_DIR"/commands/*.sh "$ROOT_DIR"/lib/*.sh; do
    # `set -e` inside a sourced lib is only a bug if it is not immediately
    # undone; the pattern to catch is a bare `set -e` that is never paired.
    if grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*e' "$f" 2>/dev/null; then
        if ! grep -qE '^[[:space:]]*set[[:space:]]+\+e' "$f" 2>/dev/null; then
            finding "$f turns on errexit with no matching 'set +e'" \
                "a sourced lib must not change errexit for its caller"
            leak_files=$((leak_files + 1))
        fi
    fi
done
(( leak_files == 0 )) && ok "no library file enables errexit"

# And the direct check: does the install loop still abort on failure?
if [[ -f "$ROOT_DIR/lib/installer/install_packages.sh" ]]; then
    if grep -qE 'set[[:space:]]+-[a-z]*e$' "$ROOT_DIR/lib/installer/install_packages.sh"; then
        finding "install_packages.sh still contains a bare 'set -e'" \
            "use: if hyprx_pkg_install \"\$pkg\"; then status=0; else status=\$?; fi"
    else
        ok "install_packages.sh does not touch errexit"
    fi

    if grep -q 'if hyprx_pkg_install' "$ROOT_DIR/lib/installer/install_packages.sh"; then
        ok "the install loop uses 'if' to capture status"
    else
        finding "install_packages.sh does not guard the install call"
    fi
fi

# ===========================================================================
# B. services.list was never acted on
# ===========================================================================
# README claimed the installer enabled services.list. Nothing did. Only doctor
# read the file, so every service was permanently reported as not-enabled.
section "B. services.list is actually enabled"

if grep -rq 'systemctl.*enable' "$ROOT_DIR/lib/" 2>/dev/null; then
    ok "lib/ contains a systemctl enable path"
else
    finding "no systemctl enable anywhere in lib/" \
        "README.md:15 and commands/install.sh:20 both promise this"
fi

if [[ -f "$ROOT_DIR/lib/installer/services.sh" ]]; then
    ok "lib/installer/services.sh exists"
    if grep -q 'services.sh' "$ROOT_DIR/lib/bootstrap.sh"; then
        ok "bootstrap sources it"
    else
        finding "services.sh is not sourced by bootstrap"
    fi
    if grep -q 'hyprx_services_enable' "$ROOT_DIR/lib/installer/engine.sh"; then
        ok "the engine calls it"
    else
        finding "the engine never calls hyprx_services_enable"
    fi
else
    finding "lib/installer/services.sh is missing"
fi

# ===========================================================================
# C. wallust template dropped CSS variables
# ===========================================================================
# wallust overwrites styles/colors.css on the FIRST wallpaper change. Five
# variables existed only in the committed default, so after that change GTK
# dropped every rule using them and the bar silently lost its styling - while a
# fresh clone looked perfect, which is why it shipped.
section "C. wallust template / stylesheet variable contract"

colour_vars() {
    grep -oE '^\s*@define-color\s+[a-zA-Z0-9_-]+' "$1" 2>/dev/null | awk '{print "@"$2}' | sort -u
}
used_vars() {
    grep -ohE '@[a-zA-Z0-9_-]+' "$@" 2>/dev/null \
        | grep -vE '^@(import|define-color|media|keyframes|supports)$' | sort -u
}

for pair in \
    "waybar-colors.css:$ROOT_DIR/config/waybar/styles" \
    "swaync-colors.css:$ROOT_DIR/config/swaync" \
    "wlogout-colors.css:$ROOT_DIR/config/wlogout"
do
    tpl="$ROOT_DIR/config/wallust/templates/${pair%%:*}"
    dir="${pair#*:}"

    [[ -f "$tpl" ]] || { finding "missing template ${pair%%:*}"; continue; }

    check_covers "${pair%%:*} covers every variable its consumer uses" \
        "${pair%%:*} does not define" \
        "GTK drops every rule using an undefined custom property" \
        <(colour_vars "$tpl") <(used_vars "$dir"/*.css)
done

# The committed default must match the template, or the fresh clone and the
# live bar disagree.
if [[ -f "$ROOT_DIR/config/waybar/styles/colors.css" ]]; then
    check_files_equal \
        "committed default and template declare the same variables" \
        "the committed default and the template declare different variables" \
        "diff <(comm -3 <(...) <(...))" \
        <(colour_vars "$ROOT_DIR/config/waybar/styles/colors.css") \
        <(colour_vars "$ROOT_DIR/config/wallust/templates/waybar-colors.css")
fi

# ===========================================================================
# D. undeclared dependencies
# ===========================================================================
# Seven binaries referenced by the config, installed by nothing, each failing
# silently. This was the bug CLASS, not seven coincidences.
section "D. dependency manifest"

MANIFEST="$ROOT_DIR/database/binary-providers.conf"
if [[ -f "$MANIFEST" ]]; then
    ok "database/binary-providers.conf exists"

    while IFS='|' read -r binary provider _rest; do
        binary="$(echo "$binary" | xargs)"
        provider="$(echo "$provider" | xargs)"
        [[ -z "$binary" ]] && continue
        [[ "$provider" == "system" ]] && continue

        if grep -qx "$provider" "$ROOT_DIR/packages.list"; then
            continue
        fi
        if $pacman_ok && pacman -Si "$provider" >/dev/null 2>&1; then
            continue
        fi
        finding "'$binary' needs '$provider', which is neither in packages.list nor in the repos" \
            "the binary will not exist at runtime, and nothing will say so"
    done <"$MANIFEST"
else
    finding "database/binary-providers.conf is missing - the guard does not exist"
fi

# Direct spot-checks on the packages that were absent.
for pkg in hyprpaper libnotify pipewire wireplumber xdg-desktop-portal-hyprland \
           hyprpolkitagent inetutils fontconfig; do
    if grep -qx "$pkg" "$ROOT_DIR/packages.list"; then
        ok "packages.list has $pkg"
    else
        finding "packages.list is missing $pkg"
    fi
done

# A service whose package is absent cannot start.
while IFS= read -r svc; do
    svc="${svc// /}"
    [[ -z "$svc" ]] && continue
    # Only services whose package this rice is expected to provide.
    #
    # docker is in services.list but deliberately NOT in packages.list: it is a
    # general-purpose daemon nothing here depends on, and services.sh reports it
    # as "no unit file" rather than failing the install. Anything not in this
    # table is skipped for the same reason - services.list is a wish list, not a
    # guarantee that every entry has a package.
    case "$svc" in
        bluetooth) pkg=bluez ;;
        firewalld) pkg=firewalld ;;
        NetworkManager) pkg=networkmanager ;;
        pipewire) pkg=pipewire ;;
        supergfxd) pkg=supergfxctl ;;
        asusd) pkg=asusctl ;;
        *) continue ;;
    esac
    grep -qx "$pkg" "$ROOT_DIR/packages.list" \
        || finding "services.list enables '$svc' but packages.list has no '$pkg'" \
            "a service for a package that is not installed cannot start"
done <"$ROOT_DIR/services.list"

# ===========================================================================
# E. fonts: Caudex only, no whole-catalogue package
# ===========================================================================
section "E. fonts"

if grep -rq 'JetBrains' "$ROOT_DIR/config" 2>/dev/null; then
    finding "JetBrainsMono is still referenced in config/" \
        "$(grep -rl JetBrains "$ROOT_DIR/config" | tr '\n' ' ')"
else
    ok "no JetBrainsMono references in config/"
fi

if grep -qE '^[[:space:]]*ttf-google-fonts' "$ROOT_DIR/packages.list"; then
    finding "ttf-google-fonts-git is installed for a single serif face" \
        "it depends on 22 further font packages and installs the whole Google catalogue"
else
    ok "the Google-catalogue font package is not installed"
fi

if [[ -f "$ROOT_DIR/lib/installer/fonts.sh" ]]; then
    pins="$(grep -oE 'Caudex-[A-Za-z]+\.ttf\|[0-9a-f]{64}' "$ROOT_DIR/lib/installer/fonts.sh" | sort -u | wc -l | tr -d ' ')"
    if [[ "$pins" == "4" ]]; then
        ok "4 distinct SHA256-pinned Caudex files"
    else
        finding "expected 4 pinned Caudex files, found $pins"
    fi

    # An unverifiable hash must be a failure, not a silent install.
    # Two distinct refusals, both required: a file whose hash does not match, and
    # a machine with no sha256 tool at all (where "verify" would silently mean
    # "trust").
    if grep -q 'Checksum mismatch' "$ROOT_DIR/lib/installer/fonts.sh"; then
        ok "font install refuses a checksum mismatch"
    else
        finding "font install does not report a checksum mismatch"
    fi
    if grep -q 'refusing to install unverified' "$ROOT_DIR/lib/installer/fonts.sh"; then
        ok "font install refuses to install unverified files with no sha256 tool"
    else
        finding "font install would install unverified files when sha256sum is missing"
    fi
else
    finding "lib/installer/fonts.sh is missing"
fi

# ===========================================================================
# F. entrypoint hardening
# ===========================================================================
# bin/hyprx built a path from $1 and sourced it, so `hyprx ../../evil` executed
# an arbitrary file. It also has no .sh suffix, so no linter ever saw it.
section "F. entrypoint hardening"

if grep -qE '\$\{?1\}?|COMMAND' "$ROOT_DIR/bin/hyprx" 2>/dev/null; then :; fi
if grep -qE '\^\[a-z\]\[a-z0-9_-\]\*\$' "$ROOT_DIR/bin/hyprx"; then
    ok "bin/hyprx validates the command name before dispatch"
else
    finding "bin/hyprx does not validate COMMAND" \
        "an unvalidated \$1 becomes a sourced path: hyprx ../../evil"
fi

if grep -q "bin/hyprx" "$ROOT_DIR/.github/workflows/tests.yml"; then
    ok "CI lints bin/hyprx"
else
    finding "CI does not lint bin/hyprx - it has no .sh suffix, so find -name '*.sh' skips it"
fi

if grep -q "bin/hyprx" "$ROOT_DIR/tests/run_tests.sh"; then
    ok "the test suite exercises bin/hyprx hardening"
else
    finding "the test suite does not test bin/hyprx argument handling"
fi

# ===========================================================================
# G. ShellCheck is not neutered
# ===========================================================================
# The old .shellcheckrc disabled SC2086 and SC2015 repo-wide. SC2015 is
# `A && B || C`, which is the exact shape that made clean.sh report a skip as a
# failure.
section "G. linter configuration"

# The codes must be absent from the ACTIVE disable list. Mentioning them in a
# comment explaining why they used to be disabled is fine and desirable.
active_disable="$(grep -oE '^[[:space:]]*disable=.*' "$ROOT_DIR/.shellcheckrc" 2>/dev/null)"
for code in SC2086 SC2015; do
    if [[ "$active_disable" == *"$code"* ]]; then
        finding "$code is still disabled repo-wide in .shellcheckrc" \
            "the active list is: $active_disable"
    else
        ok "$code is enabled"
    fi
done

# CI must read .shellcheckrc rather than keeping its own copy of the list.
if grep -qE 'shellcheck -x -e ' "$ROOT_DIR/.github/workflows/tests.yml"; then
    finding "CI still passes an inline -e exclusion list" \
        "it duplicates .shellcheckrc and the two can drift"
else
    ok "CI reads .shellcheckrc"
fi

# ===========================================================================
# H. config: validate before write
# ===========================================================================
# A rejected set used to reset the key to its DEFAULT while printing "Current
# value left unchanged". The suite asserted the buggy behaviour.
section "H. config validation"

if grep -q 'hyprx_config_validate' "$ROOT_DIR/lib/config.sh"; then
    # Scoped to hyprx_config_set's own body, and the validate call must come
    # before the save. A whole-file comparison is not good enough: hyprx_config_save
    # is DEFINED earlier in the file than hyprx_config_set, so comparing the
    # first match of each would compare a definition against a call site.
    set_body="$(sed -n '/^hyprx_config_set()/,/^}/p' "$ROOT_DIR/lib/config.sh")"

    body_validate="$(grep -n 'hyprx_config_validate' <<<"$set_body" | head -n1 | cut -d: -f1)"
    body_save="$(grep -n 'hyprx_config_save' <<<"$set_body" | head -n1 | cut -d: -f1)"

    if [[ -z "$body_validate" ]]; then
        finding "hyprx_config_set performs no validation" \
            "a rejected value would persist, then be 'reverted' to the default"
    elif [[ -z "$body_save" ]]; then
        finding "hyprx_config_set never saves"
    elif (( body_validate < body_save )); then
        ok "hyprx_config_set validates (line $body_validate) before saving (line $body_save)"
    else
        finding "hyprx_config_set saves (line $body_save) before validating (line $body_validate)" \
            "a rejected value would persist and then be 'reverted' to the default"
    fi
else
    finding "hyprx_config_set performs no validation at all"
fi

# Scoped to the `set)` case block and to real code, not comments: the `unset)`
# action legitimately calls hyprx_config_unset, and the `set)` block's comment
# explains the bug that was removed. A whole-file grep flags both.
set_block="$(sed -n '/^[[:space:]]*set)/,/^[[:space:]]*;;/p' "$ROOT_DIR/commands/config.sh" \
    | grep -vE '^[[:space:]]*#')"

if grep -qE 'hyprx_config_unset' <<<"$set_block"; then
    finding "the 'config set' branch still calls hyprx_config_unset" \
        "that restores the DEFAULT, not the previous value, while claiming the value is unchanged"
else
    ok "the 'config set' branch does not revert a rejected value"
fi

# THEME must accept a file, not only a directory.
#
# This grepped for the OLD literal code, and did so in a BRE: `\$` immediately
# followed by `\{`, where `\{` opens an interval expression. grep could not
# compile the pattern and exited 2. The caller tests non-zero as "no match",
# took the else branch, and printed "THEME validation accepts files" on every
# run regardless of what the code said - while "Unmatched \{" went to stderr.
#
# So the branch is extracted from the real function and tested with -F (fixed
# strings), which cannot fail to compile, and a missing branch is its own
# finding rather than a silent pass.
theme_branch="$(
    sed -n '/^hyprx_config_validate()/,/^}/p' "$ROOT_DIR/lib/config.sh" \
        | sed -n '/^[[:space:]]*THEME)/,/;;/p' \
        | grep -vE '^[[:space:]]*#'
)"

if [[ -z "$theme_branch" ]]; then
    finding "could not locate the THEME branch of hyprx_config_validate" \
        "the validation moved; update this check rather than leave it permanently green"
elif grep -qF -- '-d ' <<<"$theme_branch"; then
    finding "THEME validation still tests with -d" \
        "a theme is a .css FILE: config/waybar/themes/ holds one-dark.css, so -d rejects the only shipped theme"
elif grep -qF -- '-e ' <<<"$theme_branch"; then
    ok "THEME validation accepts files"
else
    finding "THEME branch tests neither -e nor -d" \
        "it must accept a file; -e covers both a file and a directory"
fi

# ===========================================================================
# I. doctor tells the truth
# ===========================================================================
# `hyprx doctor --only applications` printed nine red X and then
# "All checks passed", exiting 0. The Applications section bypassed the tallies.
section "I. doctor exit codes"

if grep -q 'check_app' "$ROOT_DIR/commands/doctor.sh"; then
    ok "the Applications section routes through the note helpers"
else
    finding "the Applications section still bypasses the tallies" \
        "a missing app prints a red X but does not affect the exit code"
fi

# --json must carry the whole report. It rejected --only on the grounds that a
# partial document would look complete, while omitting four sections entirely.
for probe in hypr_table_row "doctor_json_add"; do
    if grep -q "$probe" "$ROOT_DIR/commands/doctor.sh"; then
        ok "doctor still references $probe"
    fi
done

if grep -q 'doctor_wants fonts' "$ROOT_DIR/commands/doctor.sh" \
   && grep -q 'doctor_wants manifest' "$ROOT_DIR/commands/doctor.sh"; then
    ok "the fonts and manifest sections exist and are selectable"
else
    finding "the fonts or manifest section is missing"
fi

# ===========================================================================
# J. clean measures what it claims to measure
# ===========================================================================
section "J. clean accounting"

# The trash step added the full pre-trash size unconditionally.
if grep -qE 'gio trash --empty' "$ROOT_DIR/commands/clean.sh"; then
    if grep -q 'trash_delta' "$ROOT_DIR/commands/clean.sh"; then
        ok "the trash step measures before/after"
    else
        finding "the trash step still adds its size without measuring" \
            "README.md:90 claims every step reports what it actually reclaimed"
    fi
fi

# A sudo skip is not a failure.
if grep -q 'SKIPPED' "$ROOT_DIR/commands/clean.sh"; then
    ok "skipped steps are counted separately from failures"
else
    finding "an unauthenticated-sudo skip still exits 1" \
        "README.md:109-110 says the run still completes"
fi

# LOG_KEEP and HYPRX_LOG_KEEP must be the same knob.
if grep -q 'export HYPRX_LOG_KEEP' "$ROOT_DIR/commands/clean.sh"; then
    ok "clean exports HYPRX_LOG_KEEP so the logger and the pruner agree"
else
    finding "clean's LOG_KEEP and logger's HYPRX_LOG_KEEP are still unrelated numbers"
fi

# /tmp cleanup must be scoped.
if grep -qE 'find /tmp -mindepth 1 -user' "$ROOT_DIR/commands/clean.sh"; then
    finding "clean still walks all of /tmp for the current user's files" \
        "-mtime on a directory does not describe its contents, so a live socket in an old directory is removed with it"
else
    ok "/tmp cleanup is scoped to /tmp/\$USER"
fi

# ===========================================================================
# K. the test suite is not asserting on its own source
# ===========================================================================
# 330 tests passed while a fatal install bug shipped. Many asserted that a file
# contained a string rather than that the code behaved.
section "K. test suite integrity"

# The permissions check used to run `fail` inside a pipeline subshell, where the
# counter was incremented in a process that then exited. So the check printed
# its [FAIL] lines and still reported FAILED=0 - it could not fail.
#
# Only real code is examined. The body considered is the piped `while`'s OWN
# body - from the `| while` up to its matching `done` - not a fixed window of
# lines: a window bleeds into the enclosing loop and flags a subshell whose body
# only prints.
pipeline_loops=0
suite_lines="$(wc -l <"$ROOT_DIR/tests/run_tests.sh")"
lineno=1
while (( lineno <= suite_lines )); do
    line="$(sed -n "${lineno}p" "$ROOT_DIR/tests/run_tests.sh")"

    # Comment lines are skipped: the suite documents this very bug in prose
    # ("Process substitution, NOT `find | while`"), and that sentence matches
    # the pattern perfectly while describing code that no longer exists.
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        lineno=$((lineno + 1))
        continue
    fi

    if [[ "$line" =~ \|[[:space:]]*while ]]; then
        while_indent="${line%%[! ]*}"
        body=""
        cursor=$((lineno + 1))
        while (( cursor <= suite_lines )); do
            body_line="$(sed -n "${cursor}p" "$ROOT_DIR/tests/run_tests.sh")"
            if [[ "$body_line" =~ ^[[:space:]]*done ]]; then
                body_indent="${body_line%%[! ]*}"
                if (( ${#body_indent} <= ${#while_indent} )); then
                    break
                fi
            fi
            body+="$body_line"$'\n'
            cursor=$((cursor + 1))
        done

        if grep -qE '(^|[[:space:]])(pass|fail)[[:space:]]' <<<"$body"; then
            finding "tests/run_tests.sh:$lineno pipes into a while whose body calls pass/fail" \
                "the right side of a pipeline is a subshell: FAILED is incremented in a process that then exits, so the check cannot fail"
            pipeline_loops=$((pipeline_loops + 1))
        fi
        lineno=$cursor
    fi
    lineno=$((lineno + 1))
done
(( pipeline_loops == 0 )) && ok "no pass/fail inside a pipeline subshell"

# Every declared keybind target must exist.
missing_targets=0
while IFS= read -r ref; do
    [[ "$ref" == *"{"* ]] && continue
    case "$ref" in
        */.config/waybar/scripts/*) p="$ROOT_DIR/config/waybar/scripts/${ref##*/}" ;;
        */.local/share/hyprx/scripts/*) p="$ROOT_DIR/scripts/${ref##*/}" ;;
        *) p="$ROOT_DIR/${ref#\~/}" ;;
    esac
    [[ -e "$p" ]] || { finding "hyprland.lua autostarts a path that does not exist: $ref"; missing_targets=$((missing_targets + 1)); }
done < <(grep -oE '(~/\.config/waybar/scripts/|~/\.local/share/hyprx/scripts/)[A-Za-z0-9._-]+\.sh' \
         "$ROOT_DIR/config/hypr/hyprland.lua" 2>/dev/null | sort -u)
(( missing_targets == 0 )) && ok "every autostarted script exists"

# The suite must actually drive `hyprx install` through the CLI, which it never
# did - so nothing could observe what the install stage returned.
# Single-quoted on purpose: the literal $ is part of the pattern being searched
# for in the other file, not something to expand here.
if grep -q 'E2E_CLI" install' "$ROOT_DIR/tests/run_tests.sh"; then  # shellcheck disable=SC2016
    ok "the suite drives 'hyprx install' end to end"
else
    finding "the suite never invokes 'hyprx install' through the CLI" \
        "that is why a fatal install-loop bug shipped with 330 green tests"
fi

# ===========================================================================
# L. dead code
# ===========================================================================
section "L. dead code"

for script in battery network player power music; do
    f="$ROOT_DIR/config/waybar/scripts/$script.sh"
    [[ -f "$f" ]] || continue
    refs="$(grep -rl "$script.sh" \
        "$ROOT_DIR/config/waybar/config.jsonc" "$ROOT_DIR/config/hypr/hyprland.lua" \
        "$ROOT_DIR/scripts" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$refs" == "0" ]]; then
        finding "config/waybar/scripts/$script.sh is referenced by nothing" \
            "waybar uses its built-in battery/network module instead"
        if $FIX; then rm -f "$f"; fixed "removed $script.sh"; fi
    else
        ok "$script.sh is referenced"
    fi
done

# Empty hyprlock labels render nothing.
empty_labels="$(grep -cE '^[[:space:]]*text[[:space:]]*=[[:space:]]*$' "$ROOT_DIR/config/hypr/hyprlock.conf" 2>/dev/null)"
if [[ "$empty_labels" == "0" ]]; then
    ok "no empty hyprlock labels"
else
    finding "$empty_labels hyprlock label(s) have an empty text - they render nothing"
fi

# ===========================================================================
# M. the gate
# ===========================================================================
# preflight.sh and compatibility.sh probed the same six facts and disagreed
# about three of them. Merged into lib/installer/gate.sh.
section "M. the preflight gate"

if [[ -f "$ROOT_DIR/lib/installer/gate.sh" ]]; then
    ok "lib/installer/gate.sh exists"
else
    finding "lib/installer/gate.sh is missing"
fi

for gone in preflight.sh compatibility.sh; do
    if [[ -f "$ROOT_DIR/lib/installer/$gone" ]]; then
        finding "$gone still exists - the duplicate probe set is back"
    else
        ok "$gone is gone"
    fi
done

# A missing probe tool must never read as an unreachable network. It once
# required `ping`, which ships in iputils and is in no package list here, so on
# a minimal system the gate aborted the install.
gate_code="$(grep -vE '^[[:space:]]*#' "$ROOT_DIR/lib/installer/gate.sh" 2>/dev/null)"
if grep -q 'hyprx_gate_internet_state' <<<"$gate_code" \
   && grep -q 'Could not verify network reachability' <<<"$gate_code"; then
    ok "the gate distinguishes an unverifiable network from an outage"
else
    finding "the gate still conflates a missing probe tool with an unreachable network" \
        "a tool that is absent must report 'unknown' and stay advisory, never fatal"
fi

# Any probe the gate shells out to must be guarded, so an absent tool falls
# through to the next rung instead of being reported as a failed check.
for probe in ping curl wget; do
    if grep -qx "$probe" "$ROOT_DIR/packages.list"; then
        ok "$probe is a declared dependency"
    elif grep -q "command -v $probe" <<<"$gate_code"; then
        ok "$probe is not declared but the gate guards it and falls through"
    else
        finding "the gate shells out to '$probe' without guarding it" \
            "'$probe' is not in packages.list, so an absent probe reads as a failed check"
    fi
done

# The engine must run the gate once.
if [[ -f "$ROOT_DIR/lib/installer/engine.sh" ]]; then
    gate_calls="$(grep -cE 'hyprx_(install_gate|preflight_check|compatibility_check)' \
        "$ROOT_DIR/lib/installer/engine.sh")"
    if [[ "$gate_calls" == "1" ]]; then
        ok "engine.sh calls the gate exactly once"
    else
        finding "engine.sh invokes a gate $gate_calls times"
    fi
fi

# The probe cache must be reachable from its callers. Every gate probe used to
# be called as `x="$(hyprx_gate_…)"`, and a command substitution is a subshell:
# the cache append happened there and was discarded on exit. The array was empty
# after every run and no test could see it, because counting probe invocations
# on a host where each probe happens to run once looks identical to caching.
subshell_probes=0
for pattern in 'hyprx_gate_probe' 'hyprx_gate_disk_kb' 'hyprx_gate_ram_mb' \
               'hyprx_gate_internet_state'; do
    # Comments are excluded: gate.sh quotes the old broken form in prose
    # ("this as `root_kb=\"$(hyprx_gate_disk_kb /)\"`"), and that sentence is
    # describing the bug rather than committing it.
    hits="$(grep -nE "\$\(.*$pattern" "$ROOT_DIR/lib/installer/gate.sh" 2>/dev/null \
        | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
    if [[ -n "$hits" ]]; then
        finding "$pattern is captured through \$(), so its cache write is lost in a subshell" \
            "pass a destination variable instead: $pattern <key> <var> …"
        subshell_probes=$((subshell_probes + 1))
    fi
done
(( subshell_probes == 0 )) && ok "no gate probe is called inside a command substitution"

# `sudo -v` refreshes the credential timestamp and can prompt for a password;
# `sudo -n true` only tests for a cached ticket and never prompts.
#
# A guarded fallback is acceptable - on a real tty, outside a dry run, there is
# nothing to gain from refusing to authenticate. An UNGUARDED one is not: it
# runs twice per install (the old pair of gates each called it) and can block on
# a prompt nobody is there to answer.
if ! grep -q 'sudo -v' <<<"$gate_code"; then
    ok "the gate never uses the prompting 'sudo -v'"
elif grep -q '\-t 0' <<<"$gate_code" && grep -q 'hyprx_util_dry_run' <<<"$gate_code"; then
    ok "'sudo -v' is only reached on a real tty, outside a dry run"
else
    finding "gate.sh calls 'sudo -v' without guarding it on a tty and dry-run check" \
        "it can block on a password prompt; prefer 'sudo -n true' and fall back only when there is a terminal to answer"
fi

# ===========================================================================
# N. one linter, one ruleset
# ===========================================================================
# The suite used to carry its own inline `-e SC2015,SC2086,…` list while CI read
# .shellcheckrc. Twelve findings passed the suite and failed CI, and nothing in
# the output said which linter was authoritative.
section "N. linter consistency"

if grep -qE 'shellcheck[^|]*-e SC' "$ROOT_DIR/tests/run_tests.sh"; then
    finding "tests/run_tests.sh still passes an inline -e exclusion list" \
        "it must read .shellcheckrc, or the suite and CI lint against different rulesets"
else
    ok "the suite lints through .shellcheckrc"
fi

if grep -q 'rcfile' "$ROOT_DIR/tests/run_tests.sh"; then
    ok "the suite passes --rcfile explicitly, so cwd cannot change the rules"
else
    finding "the suite relies on cwd to locate .shellcheckrc" \
        "ShellCheck looks for it in the current directory, so the rules change with the working directory"
fi

# CI must use the same mechanism, not the cwd-relative default.
if grep -qE 'shellcheck .*--rcfile' "$ROOT_DIR/.github/workflows/tests.yml"; then
    ok "the CI lint job also passes --rcfile explicitly"
else
    finding "the CI lint job relies on cwd to locate .shellcheckrc" \
        "one ruleset means one mechanism: pass --rcfile in both places"
fi

# ShellCheck's rule set moves between releases, so an unpinned install makes
# "passes locally" meaningless. Both jobs must pin the same version.
sc_pins="$(grep -oE 'SHELLCHECK_VERSION="v[0-9.]+"' "$ROOT_DIR/.github/workflows/tests.yml" \
    | sort -u)"
pin_count="$(grep -c 'SHELLCHECK_VERSION' "$ROOT_DIR/.github/workflows/tests.yml")"

if [[ "$pin_count" -ge 2 ]] && [[ "$(wc -l <<<"$sc_pins")" == "1" ]]; then
    ok "both CI jobs pin ShellCheck to the same version ($sc_pins)"
else
    finding "CI does not pin ShellCheck to one version across jobs" \
        "apt follows whatever ubuntu-latest ships, so the rule set drifts and local results stop predicting CI"
fi

# SC2015 is the shape that produced a real bug: clean.sh reported an
# unauthenticated-sudo SKIP as a FAILURE. It must not creep back in.
#
# Asked of ShellCheck directly rather than grepped for. A grep for `&&` and `||`
# on one line cannot tell `A && B || C` from `[[ A && B ]] || C`, and an
# earlier version of this check did exactly that - flagging six correct lines
# while missing three real ones. ShellCheck is the authority, and CI now pins
# its version, so "ShellCheck says no" is a reproducible answer.
if command -v shellcheck >/dev/null 2>&1; then
    sc2015_out="$(
        find "$ROOT_DIR/lib" "$ROOT_DIR/commands" "$ROOT_DIR/scripts" \
            -name '*.sh' -type f -print0 \
        | xargs -0 shellcheck -x --rcfile "$ROOT_DIR/.shellcheckrc" \
            -f gcc 2>&1 \
        | grep -oE '\[SC2015\]' | wc -l | tr -d ' '
    )"
    sc2015_out="${sc2015_out:-0}"
    if (( sc2015_out == 0 )); then
        ok "ShellCheck reports no SC2015 ('A && B || C') in lib/, commands/ or scripts/"
    else
        finding "ShellCheck reports $sc2015_out SC2015 finding(s)" \
            "'A && B || C' is not if-then-else; C runs whenever B fails. Replace with an explicit if/then."
    fi
else
    hyprx_ui_info "shellcheck not available - skipping the SC2015 check"
fi

# ===========================================================================
# O. tools the tests shell out to
# ===========================================================================
# The same failure mode as the gate's `ping`, one layer down. `diff` was absent
# from the CI container, so `if diff -q a b` exited 127, the else branch ran,
# and the suite accused the FILE CONTENTS of differing - with an empty diff.
# Worse, tools invoked inside $( ) fail silently: `comm -23 a b` yields "" when
# comm cannot run, and every caller tested for "", so a missing comm reported a
# PASSING assertion.
section "O. test tool prerequisites"

suite="$ROOT_DIR/tests/run_tests.sh"

# The suite must check its own tools before using them.
if grep -qE 'Testing suite prerequisites|section_start "suite prerequisites"' "$suite"; then
    ok "the suite asserts its own tool prerequisites up front"
else
    finding "the suite does not verify the tools it shells out to" \
        "a missing diff/comm/sort/awk must fail loudly, not masquerade as an assertion result"
fi

# And it must distinguish 'files differ' from 'diff did not run'. Both are
# non-zero; treating them alike is how a missing binary became an accusation.
if grep -q 'no-diff-tool' "$suite"; then
    ok "a failed diff is distinguished from a differing file"
else
    finding "a non-zero 'diff' is read as 'the files differ'" \
        "exit 127 (not found) and exit 1 (differ) are both non-zero; report them apart"
fi

# Every file-comparison assertion should go through the helper rather than call
# diff directly. A raw `diff` outside the helper can reintroduce the conflation.
#
# Both greps below need care or they flag the checker's own prose: comment lines
# quote the bug verbatim ("if diff -q a b"), the helper bodies contain the one
# legitimate call, and section O's own pattern definitions contain the literal
# `)diff -q` and `)comm -23` they are searching for - which would make the check
# report itself. All three are stripped; only what remains is inspected.
#
# review-checks.sh is scanned too, not only the suite: this script had exactly
# this defect in its own section C, and a checker that exempts itself is not
# one.
suite_code_no_helpers="$(
    awk '
        /^(files_equal|assert_covers|check_covers|check_files_equal)\(\) \{/ { skip = 1 }
        skip && /^\}/                                                       { skip = 0; next }
        skip                                                                 { next }
        /^[[:space:]]*#/                                                     { next }
        /raw_(diff|comm)=/                                                   { next }
        { print }
    ' "$suite" "$ROOT_DIR/tests/review-checks.sh"
)"

raw_diff="$(grep -E '(^|[^_a-z])diff -q' <<<"$suite_code_no_helpers" || true)"
if [[ -z "$raw_diff" ]]; then
    ok "no file comparison bypasses the files_equal helpers"
else
    # The message deliberately does not spell out the pattern: it would then
    # contain the very text this grep looks for, and the check would flag itself.
    finding "raw diff invocation outside a helper: $(head -1 <<<"$raw_diff" | cut -c1-60)" \
        "use files_equal/check_files_equal, which report 'tool missing' instead of 'differ'"
fi

# comm inside $( ) is the vacuous-pass shape. Every use should be the helper
# that captures the exit status.
raw_comm="$(grep -E '(^|[^_a-z])comm -23' <<<"$suite_code_no_helpers" || true)"
if [[ -z "$raw_comm" ]]; then
    ok "every 'comm' comparison captures its exit status"
else
    finding "raw comm invocation outside a helper: $(head -1 <<<"$raw_comm" | cut -c1-60)" \
        "a missing comm yields empty output, which callers read as 'nothing missing'"
fi

# A grep pattern that will not COMPILE makes grep exit 2, which is non-zero
# exactly like a genuine miss - so the else branch runs and the check reports
# OK forever. This script had one (section H, THEME validation), and it printed
# "Unmatched \{" to stderr on every run while staying green.
compile_broken=""
for script in "$ROOT_DIR/tests/review-checks.sh" "$ROOT_DIR/tests/run_tests.sh"; do
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        compile_broken+="  ${script##*/}: $hit"$'\n'
    done < <(broken_grep_patterns "$script")
done

if [[ -z "$compile_broken" ]]; then
    ok "every grep pattern in the test scripts compiles"
else
    finding "grep patterns that fail to compile:" \
        "grep exits 2, callers test non-zero as 'no match', and the check passes unconditionally"
    printf '%s' "$compile_broken"
fi

# CI must install what the suite needs. diffutils is not in archlinux:base.
#
# The word has to be looked for in the INSTALL COMMAND, not in the file: an
# earlier version of this check grepped the whole workflow and passed after
# the package was deleted from `pacman -Syy`, because the explanatory comment
# above the command still said "diffutils". A check that its own documentation
# satisfies is not a check.
ci_install_cmds="$(grep -E '^[[:space:]]*(pacman|sudo apt|apt) ' \
    "$ROOT_DIR/.github/workflows/tests.yml" | grep -v '^[[:space:]]*#' || true)"

if grep -q 'diffutils' <<<"$ci_install_cmds"; then
    ok "the test-suite CI job installs diffutils"
elif ! grep -q 'archlinux:base\|pacman -Syy' <<<"$ci_install_cmds"; then
    hyprx_ui_info "no pacman install line found - skipping the diffutils check"
else
    finding "the CI install command does not include diffutils" \
        "the suite compares files with diff; archlinux:base does not ship it"
fi

# ===========================================================================
# P. the verdict reaches the exit code
# ===========================================================================
# engine.sh decides the run's verdict with `hyprx_X || return 1` and with
# `hyprx_X || rc=$?`. The second form only means anything if X can return
# non-zero - a function's status is the status of its LAST command, so one that
# ends on `if`, `mapfile` or `echo` cannot fail no matter what happened.
#
# Four stages could not, so four guards read like safety nets and were not:
#
#   hyprx_validator_validate  ended on `if cond; then ... fi`
#   hyprx_resolver_resolve    ended on `mapfile`
#   hyprx_deploy_all          ended on `hyprx_snapshot_write_deployed`
#   hyprx_report_generate     ended on `echo`
#
# The validator one shipped: an install whose queue named a package that does
# not exist printed "Package not found", deployed every config, wrote a report,
# printed "Installation completed successfully" and exited 0. A run that had NOT
# done the thing reported that it had.
section "P. the verdict reaches the exit code"

ENGINE="$ROOT_DIR/lib/installer/engine.sh"

dead_guards=()
while IFS= read -r callee; do
    [[ -z "$callee" ]] && continue
    def_file="$(grep -rl "^${callee}()" "$ROOT_DIR/lib" 2>/dev/null | head -1)"
    if [[ -z "$def_file" ]]; then
        dead_guards+=("$callee (not defined)")
        continue
    fi
    def_line="$(grep -n "^${callee}()" "$def_file" | head -1 | cut -d: -f1)"
    if ! awk -v s="$def_line" '
        NR>s && /^}$/            { exit }
        NR>s && /return 1/       { found=1 }
        END { exit found ? 0 : 1 }' "$def_file"; then
        dead_guards+=("$callee ($def_file)")
    fi
done < <(grep -oE '^[[:space:]]*hyprx_[a-z_]+ \|\| return 1' "$ENGINE" 2>/dev/null \
         | grep -oE 'hyprx_[a-z_]+' | sort -u)

guard_total="$(grep -cE '^[[:space:]]*hyprx_[a-z_]+ \|\| return 1' "$ENGINE" 2>/dev/null || true)"

if (( guard_total == 0 )); then
    finding "no 'hyprx_X || return 1' stages found in engine.sh" \
        "this check reads engine.sh; if it cannot find the pattern it is checking nothing"
elif (( ${#dead_guards[@]} > 0 )); then
    finding "engine.sh guards a stage that cannot return 1: ${dead_guards[*]}" \
        "a guard on something that always exits 0 is not a guard - it reads like one"
else
    ok "all $guard_total '|| return 1' stages in engine.sh can return 1"
fi

# A captured rc only counts if it is also tallied. Capturing without counting is
# the same omission one stage later.
uncounted=()
while IFS= read -r rc; do
    [[ -z "$rc" ]] && continue
    if ! grep -qE "\(\( ${rc} != 0 \)\)" "$ENGINE"; then
        uncounted+=("$rc")
    fi
done < <(grep -oE '^[[:space:]]*local [a-z_]+_rc=0' "$ENGINE" | grep -oE '[a-z_]+_rc' | sort -u)

rc_total="$(grep -cE '^[[:space:]]*local [a-z_]+_rc=0' "$ENGINE" 2>/dev/null || true)"
if (( rc_total == 0 )); then
    finding "no 'local X_rc=0' captures found in engine.sh" \
        "this check reads engine.sh; if it cannot find the pattern it is checking nothing"
elif (( ${#uncounted[@]} > 0 )); then
    finding "engine.sh captures ${uncounted[*]} but never tests it" \
        "a captured exit code that is not tallied changes nothing about the verdict"
else
    ok "all $rc_total captured exit codes are tallied into the verdict"
fi

# ===========================================================================
# Q. derived state must not be written back into an exported override
# ===========================================================================
# lib/state.sh reads a set of HYPRX_* names as OVERRIDES: non-empty means "use
# this", empty or unset means derive from HYPRX_STATE_DIR. Writing a derived
# value back into one of them turns "derive it" into a frozen path - and if that
# name is exported, every child process inherits the frozen path and stops
# following HYPRX_STATE_DIR.
#
# This shipped twice, both times in the name the test suite exports as "":
#
#   logger.sh:5    HYPRX_LOGGER_DIR="$HYPRX_STATE_DIR"
#   recovery.sh:6  HYPRX_RECOVERY_STATE_DIR="$HYPRX_STATE_RECOVERY_DIR"
#
# state.sh:28-30 then used the inherited HYPRX_LOGGER_DIR to OVERRIDE the child's
# own HYPRX_STATE_DIR. Every log, snapshot, backup and install.state from the
# end-to-end install went to the suite-level dir while the assertions looked in
# the e2e one - so "install.state cleared on success" and "install.state cleared
# after a partial install" passed without having looked at the file the install
# actually wrote.
section "Q. derived state must not be written back into an exported override"

overrides="$(grep -oE '\$\{HYPRX_[A-Z0-9_]+:-' "$ROOT_DIR/lib/state.sh" 2>/dev/null \
            | sed 's/^\${//; s/:-$//' | sort -u || true)"
exported="$(grep -rhoE 'export[[:space:]]+HYPRX_[A-Z0-9_]+' "$ROOT_DIR/tests" 2>/dev/null \
            | awk '{print $2}' | sort -u || true)"

# Intersected with a shell loop rather than `comm -12`: an absent comm yields
# no output, which would read as "no override is at risk" and report a pass for a
# check that never ran. That is this script's own recurring bug, so it does not
# get to commit it here.
at_risk=""
while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if grep -qx "$name" <<<"$exported"; then
        at_risk+="$name"$'\n'
    fi
done <<<"$overrides"

if [[ -z "$overrides" || -z "$exported" ]]; then
    finding "could not determine the override/exported sets" \
        "state.sh's \${HYPRX_...:-} pattern or the suite's exports were not found"
elif [[ -z "$at_risk" ]]; then
    ok "no state override is both exported by the suite and derived elsewhere"
else
    writebacks=()
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue
            writebacks+=("$hit")
        done < <(grep -rn "^[[:space:]]*${name}=" "$ROOT_DIR/lib" "$ROOT_DIR/commands" 2>/dev/null \
                 | grep -v 'lib/state.sh' || true)
    done <<<"$at_risk"

    if (( ${#writebacks[@]} == 0 )); then
        ok "no exported override ($(tr '\n' ' ' <<<"$at_risk")) is written back to"
    else
        finding "a derived value is written back into an exported override:" \
            "$(printf '%s; ' "${writebacks[@]}")" \
            "an exported derived path is inherited by every child and stops following HYPRX_STATE_DIR"
    fi
fi

# ===========================================================================
# R. systemd unit naming lives in one place
# ===========================================================================
# services.list holds bare names (`bluetooth`, `NetworkManager`) but
# `systemctl list-unit-files` matches only FULL unit names, so `NetworkManager`
# matched nothing and exited 1. Every entry answered "no unit file in either
# scope": networkmanager, pipewire, firewalld and bluez were installed and each
# was reported as absent, and the stage enabled nothing - Enabled 0, Skipped 7
# on a machine that had four of them.
#
# doctor.sh appended `.service` and services.sh did not, so the two disagreed
# about the same machine. One shared helper now owns the convention, because a
# convention enforced in two places is a convention that will drift again.
section "R. systemd unit naming lives in one place"

if ! grep -q '^hyprx_service_unit_name()' "$ROOT_DIR/lib/installer/services.sh" 2>/dev/null; then
    finding "services.sh does not define hyprx_service_unit_name" \
        "the .service suffix is the convention; without one owner it is applied ad hoc"
else
    if grep -q 'hyprx_service_unit_name' "$ROOT_DIR/lib/installer/services.sh" \
       && grep -q 'hyprx_service_unit_name' "$ROOT_DIR/commands/doctor.sh" 2>/dev/null; then
        ok "services.sh and doctor.sh share hyprx_service_unit_name"
    else
        finding "doctor.sh does not use hyprx_service_unit_name" \
            "doctor appending the suffix itself while services.sh does not is how they came to disagree"
    fi
fi

# The suite's own scope test used to be `grep -q hyprx_service_scope`, which
# asserted the function was MENTIONED and never that it resolved anything.
if grep -q 'hyprx_service_scope NetworkManager' "$ROOT_DIR/tests/run_tests.sh" 2>/dev/null; then
    ok "the suite resolves a real unit name, not just the function's presence"
else
    finding "the suite does not test scope resolution with a concrete unit name" \
        "grepping for the function's name passes even when it resolves nothing"
fi

# ===========================================================================
# Summary
# ===========================================================================
printf '\n%s\n' "========================================="
if (( FINDINGS == 0 )); then
    green "No findings. Every checkable claim in REVIEW.md is now resolved."
else
    red "$FINDINGS finding(s)."
    if (( FIXED > 0 )); then
        green "$FIXED fixed with --fix."
    fi
    info "Most of these are also asserted by tests/run_tests.sh, which is the gate."
    info "See REVIEW.md for the full analysis and the reasoning behind each."
fi
printf '%s\n' "========================================="

(( FINDINGS == 0 ))
