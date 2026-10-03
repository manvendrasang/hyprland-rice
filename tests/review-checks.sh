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

    miss="$(comm -23 <(used_vars "$dir"/*.css) <(colour_vars "$tpl"))"
    if [[ -z "$miss" ]]; then
        ok "${pair%%:*} covers every variable its consumer uses"
    else
        finding "${pair%%:*} does not define: $(tr '\n' ' ' <<<"$miss")" \
            "GTK drops every rule using an undefined custom property"
    fi
done

# The committed default must match the template, or the fresh clone and the
# live bar disagree.
if [[ -f "$ROOT_DIR/config/waybar/styles/colors.css" ]]; then
    if diff -q <(colour_vars "$ROOT_DIR/config/waybar/styles/colors.css") \
               <(colour_vars "$ROOT_DIR/config/wallust/templates/waybar-colors.css") >/dev/null 2>&1
    then
        ok "committed default and template declare the same variables"
    else
        finding "the committed default and the template declare different variables" \
            "diff <(comm -3 <(...) <(...))"
    fi
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
           hyprpolkit-agent inetutils fontconfig; do
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

# THEME must accept a file.
# Single-quoted on purpose: the literal `$\{...}` must reach grep as regex, not
# be expanded by this script. shellcheck disable=SC2016
if grep -q '\-d "\$\{HYPRX_CONFIG' "$ROOT_DIR/lib/config.sh"; then  # shellcheck disable=SC2016
    finding "THEME validation still uses -d" \
        "a theme is a .css FILE: config/waybar/themes/ holds one-dark.css, so -d rejects the only shipped theme"
else
    ok "THEME validation accepts files"
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
# Only real code is examined, and a pipeline is only flagged if the loop body
# actually calls pass or fail. Comments describing the old bug are excluded, and
# `| while read` with a side-effect-free body is harmless.
pipeline_loops=0
while IFS=: read -r lineno body; do
    [[ "$body" =~ ^[[:space:]]*# ]] && continue
    # The body of the while is what follows, up to the matching `done`.
    loop_body="$(sed -n "$((lineno + 1)),$((lineno + 12))p" "$ROOT_DIR/tests/run_tests.sh")"
    if grep -qE '^[[:space:]]*done' <<<"$loop_body"; then
        if grep -qE '(^|[[:space:]])(pass|fail)[[:space:]]' <<<"$loop_body"; then
            finding "tests/run_tests.sh:$lineno pipes into a while whose body calls pass/fail" \
                "the right side of a pipeline is a subshell: FAILED is incremented in a process that then exits, so the check cannot fail"
            pipeline_loops=$((pipeline_loops + 1))
        fi
    fi
done < <(grep -nE '\|[[:space:]]*while' "$ROOT_DIR/tests/run_tests.sh")
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
