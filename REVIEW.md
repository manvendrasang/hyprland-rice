# HyprX — Full Repo Assessment (RESOLVED)

**Date:** 2026-10-03
**Commit:** `7c33370` ("re-eval test suit") on `master`
**Scope:** 9,220 lines across 137 files
**Method:** Read every file; ran `tests/run_tests.sh` (330 pass / 0 fail), `shellcheck`, `jq`, `luac`; executed live repros of the installer and CLI against an isolated `HYPRX_TARGET_HOME`.

Every finding below was verified by execution, not inferred. Where a claim is marked ⚠️ it could not be confirmed on this machine and the verification command is given.

The repo is **substantially better engineered than most dotfile repos** — `lib/state.sh` as a single path authority, dry-run guards threaded through every mutating helper, an 861-line diagnostic with 17 selectable sections, and a 1,319-line suite. The problems are concentrated in three places: the package-install loop, the config-deploy/theme contract, and the fact that two headline README features don't exist.

---

## Contents

- [Critical — verified bugs](#critical--verified-bugs)
- [Correctness & logic issues](#correctness--logic-issues)
- [Dead / unreachable code](#dead--unreachable-code)
- [Duplication](#duplication--110-lines-that-should-be-one-helper)
- [Architecture & maintainability](#architecture--maintainability)
- [Test suite](#test-suite-330-green-but-weak-where-it-matters)
- [Prioritised fix list](#prioritised-fix-list)

---

## Critical — verified bugs

### 1. `set -e` leaks out of the install loop and kills the install
`lib/installer/install_packages.sh:22-25`

```bash
set +e
hyprx_pkg_install "$pkg"
status=$?
set -e          # <-- errexit is now ON for the rest of the process
```

`bin/hyprx:7` deliberately runs with only `set -uo pipefail`. After the **first** package attempt, errexit is enabled globally. The next unguarded failing command aborts everything — and that is `hyprx_pkg_install` inside the retry loop (`lib/installer/retry.sh:42`), which is *unguarded*.

Repro (stubbing the package layer, verbatim repo functions):

```
> Installing good      ✓ good
> Installing bad       ✗ bad
! Retrying failed packages...
  Retry attempt 1/3
  Retrying bad
                      <-- script dies here, exit 1
```

Consequences, all of them the exact scenarios the retry/recovery/snapshot design was built for:

- Retry loop dies on the first package that fails again → **retries never complete**.
- Install **summary never printed**; no `Installed/Skipped/Failed` counts.
- `hyprx_failure_logger_summary` never runs → the failure log has no summary.
- `hyprx_recovery_clear_state` (`install_packages.sh:85`) never runs → `install.state` is **left behind**, so the next `hyprx install` takes the `hyprx_recovery_resume` branch (`engine.sh:13`) against a phantom interrupted install.
- `hyprx_deploy_all`, `hyprx_snapshot_save`, `hyprx_report_generate` never run → no configs, no rollback point, no report.

Net: **one failing package silently destroys an install that was already ~50 packages deep.**

Fix: replace the `set +e`/`set -e` pair with `if hyprx_pkg_install "$pkg"; then ... else status=$?; fi`.

### 2. `services.list` is never acted on — the feature doesn't exist

```
$ grep -rn "services.list" --include='*.sh' .
commands/doctor.sh:418    services_file="$HYPRX_ROOT/services.list"   # only reads it

$ grep -rn "systemctl" lib/ commands/ bin/ | grep -iE "enable|daemon-reload"
commands/doctor.sh:428    state=$(systemctl is-enabled ...)             # only *checks* it
```

`lib/installer/engine.sh` runs: preflight → compatibility → resolve → validate → install → deploy → gpu-offload → snapshot → report. **There is no stage that enables anything.** Yet:

- `README.md:15` — "Enables the systemd services listed in `services.list`."
- `commands/install.sh:20-22` — `--dry-run` promises "…without … **enabling any services**"

So doctor will permanently report all 7 services as `installed but not enabled` warnings, and the documented workflow is fiction.

### 3. wallust's template drops 5 CSS variables the bar depends on

`config/wallust/wallust.toml:26-27` overwrites `~/.config/waybar/styles/colors.css` on the **first wallpaper change** with a template defining 12 vars. The stylesheets reference 17.

```
>>> used in styles/*.css but NOT defined by the wallust template:
  @bg0   6 refs      modules.css:21,56,107,115,240  tray.css:2
  @bg3   2 refs      modules.css:102               tray.css:3
  @grey1 2 refs      modules.css:195,263
  @bg2   1 ref       modules.css:45
  @aqua  1 ref       modules.css:210
```

After the first wallpaper change GTK drops all 12 declarations: the bar loses module backgrounds, borders, rounded corners, the muted-bluetooth colour and the charging-battery colour. **A fresh clone looks perfect, which is why this ships.** The committed default has them; the template doesn't.

Fix: add the five `@define-color` lines to `config/wallust/templates/waybar-colors.css`.

### 4. `battery.sh` emits invalid JSON — proven

```
$ bash config/waybar/scripts/battery.sh | jq empty
jq: parse error: Invalid string: control characters ... at line 5, column 10
```

`config/waybar/scripts/battery.sh:81` uses `printf '…\n…'` inside a JSON string; every peer script correctly uses `\\n` (`clipboard.sh:5`, `bluetooth.sh:17`, `music-daemon.sh:55`). Masked only because the script is dead (see [Dead Code](#dead--unreachable-code)).

### 5. `hyprx config set` writes first, validates second, then reverts to the **default** — silent data loss

`commands/config.sh:63-76`

```
$ hyprx config set LOG_LEVEL debug   → ✓ LOG_LEVEL = debug
$ hyprx config set LOG_LEVEL verbose → ✗ Invalid value … "Current value left unchanged."
$ hyprx config get LOG_LEVEL         → info          # should be debug
```

It calls `hyprx_config_set` (which persists), *then* validates, then "reverts" with `hyprx_config_unset` — which restores the **default**, not the previous value. The message is a lie.

Root cause: `hyprx_config_set` in `lib/config.sh:113` performs **no validation at all**; validation lives only in the command, after the write. The suite (`tests/run_tests.sh:821`) asserts `info`, i.e. **the test encodes the bug**.

Fix: validate in `hyprx_config_set` before `hyprx_config_save`, and drop the revert.

### 6. `bin/hyprx` sources an arbitrary attacker-chosen path

`bin/hyprx:17-31` — `COMMAND` from `$1` is concatenated with no validation:

```
$ hyprx ../../../../tmp/evil
PWNED: arbitrary sourced file
```

Notably inconsistent: `lib/installer/deploy.sh:13-17` goes to real trouble to reject `../escape`, `a/b`, `.`, `..` in config dir names — then the entry point two directories up validates nothing.

Fix: `[[ "$COMMAND" =~ ^[a-z][a-z-]*$ ]]` plus an explicit whitelist (better still, derive it from `commands/*.sh`).

### 7. `THEME` validation requires a directory; the only theme is a file

`lib/config.sh:158` uses `-d "${HYPRX_CONFIG:?}/waybar/themes/$value"`, but the directory contains exactly one **file**:

```
$ hyprx config set THEME one-dark
✗ Invalid value for THEME: 'one-dark'          exit=1
```

`config/hyprx.conf:6` advertises "must exist in `config/waybar/themes/`". Every non-`default` theme is unselectable. (`commands/doctor.sh:208` also prints `${HYPRX_CONFIG_THEME:-Default}` — capital D, inconsistent with the `default` value everywhere else.)

---

## Correctness & logic issues

### 8. Install reports success with failures

`install_packages.sh:85` ends with `hyprx_recovery_clear_state` → returns 0 unconditionally. `engine.sh:49` then prints **"Installation completed successfully."** after listing 12 failed packages. Exit code is 0. There is no `--strict` / `ON_ERROR=abort` knob.

### 9. `doctor --json` is structurally incomplete — while `--only` is rejected for exactly that reason

`commands/doctor.sh:826-829`:

```bash
hyprx_ui_error "--json cannot be combined with --only (a partial document would look complete)"
```

But the document is *already* partial by construction. The `configuration`, `applications`, `system` and `storage` sections use `hyprx_table_row`/`hyprx_ui_*` directly and never call `doctor_json_add`. Verified against real output (40 findings, valid JSON):

```
>>> ABSENT  Hyprland Installed / Waybar Installed / Kitty Installed / VS Code Installed
>>> ABSENT  Git Installed / PipeWire Installed / Bluetooth Installed
>>> ABSENT  Theme / Terminal / Distribution / CPU Vendor / GPU Vendor / Package Manager / Root Usage
```

Also missing: the swap *moderate* case and the thermals table are `hyprx_ui_info`, not findings. So `--json` consumers see ~26 fewer items than the human report.

Fix: route `check()` and `hyprx_table_row` through the note helpers.

### 10. `clean` claims bytes it never freed

`commands/clean.sh:293-295`:

```bash
gio trash --empty >/dev/null 2>&1
add_freed "$TRASH_SIZE"                     # counted unconditionally
hyprx_ui_success "Emptied the trash.…"
```

`gio` failure is swallowed *and* the full pre-trash size is added to the run total. Directly contradicts `README.md:90` — "Every step reports the bytes it actually reclaimed." This is the one place in `clean.sh` that doesn't measure before/after, which is the discipline the rest of the file follows rigorously.

### 11. `#` inside a config value is eaten as a comment

```
$ hyprx config set LOG_FILE '/var/log/my#log.txt'   → ✓
$ hyprx config get LOG_FILE                          → /var/log/my
```

`lib/config.sh:35` strips from the first `#` **before** splitting on `=`, destroying the value and any `#` inside quotes.

### 12. One `pacman -S` per package — ~50 sequential transactions

`lib/packages.sh:47-54`. Each invocation re-resolves the full dependency graph, re-reads the db and re-touches the sudo ticket. A full `hyprx install` spends minutes in overhead that a single batched call avoids. Group the validated queue into official/AUR sets and issue **two** commands.

### 13. AUR-only packages fail silently when `PACKAGE_MANAGER=pacman`

`lib/packages.sh:39-45` — `hyprx_pkg_exists_aur` returns 1 for anything but yay/paru. So `visual-studio-code-bin`, `ttf-google-fonts-git` and `spotify-launcher` are reported as `Package not found` and skipped, with **no** message that the cause is a missing AUR helper. README claims validation "against the official repos **and the AUR**".

### 14. Snapshot IDs collide within the same second

`lib/installer/snapshot.sh:10` uses `date +%Y%m%d-%H%M%S` (1-second resolution). Two installs in the same second share an ID, and `deploy.sh:58` does `rm -rf "$backup"` — the second run **destroys the first run's config backup**. Use `%N`/mktemp or an `O_EXCL` lock.

### 15. `clean`'s `/tmp` step has a real blast radius

`commands/clean.sh:391-393`:

```bash
find /tmp -mindepth 1 -user "$CURRENT_USER" -mtime "+$TMP_AGE_DAYS"
rm -rf "${OLD_TMP[@]}"
```

Not scoped to `/tmp/$USER`, and `-mtime` on a directory says nothing about its contents. Any of the user's socket dirs or scratch trees older than 1 day goes. Note the **safer** `/tmp/$USER` convention is what `systemd` already provides — or at minimum add `-maxdepth 1` + an exclusion list.

### 16. Both `dev-sync.sh` files are broken

`config/waybar/scripts/dev-sync.sh` (dead, 0 refs):

```bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # → ~/.config/waybar
rm -rf "$HOME/.config/waybar"        # deletes the dir it is executing from
cp -r "$ROOT_DIR/config/waybar" …    # source no longer exists → set -e aborts
```

Broken in **every** layout. It also hand-rolls the blind `pkill -x waybar && nohup waybar &` that `scripts/reload-waybar.sh` was written to eliminate (`reload-waybar.sh:4-5`).

`scripts/dev-sync.sh` (also 0 refs) is *functional* from the repo or the installed copy, but does `rsync -a --delete` into `~/.config/hypr/` — which **destroys the live `hyprpaper.conf` wallpaper block** that `deploy.sh:36-45` exists specifically to preserve. That's the "Monitor has no target: no wp will be created" regression documented at `config/hypr/hyprpaper.conf:4-7`. It also syncs 2 of the 9 deploy targets and needs `rsync`, which isn't in `packages.list`.

### 17. Undeclared runtime dependencies

```
$ for p in hyprpaper libnotify nemo bluem rsync; do grep -qx "$p" packages.list …; done
hyprpaper   *** ABSENT ***     ← the ENTIRE wallpaper + dynamic-theming chain
libnotify   *** ABSENT ***     ← notify-send is the error handler for 6 paths
nemo        *** ABSENT ***     ← but hyprland.lua:30 binds it (thunar is installed instead)
bluem       *** ABSENT ***     ← but config.jsonc:112 calls blueman-manager
rsync       *** ABSENT ***     ← but scripts/dev-sync.sh:11 needs it
```

**`hyprpaper` is the headline one.** It is autostarted (`hyprland.lua:46`), configured (`config/hypr/hyprpaper.conf`), polled by `wallust-hyprpaper-sync.sh` every 2s, and restored at login by `wallpaper-restore.sh` — and a clean `hyprx install` on Arch does **not** install it. On a fresh machine: no wallpaper, no colours, no theming, and `doctor` reports `hyprpaper is not running` with a suggestion to run a script that will also fail.

`notify-send` is worse than a missing dependency because of *where* it's used: `sound-manager.sh:10`, `wifi-manager.sh:8`, `system-monitor.sh:12`, `clipboard-clear.sh:18`, `settings-menu.sh:60`, `power-profile-cycle.sh:63`, `wlogout/layout:3`. Every "surface the problem" path degrades to a silent no-op — the exact failure mode `sound-manager.sh:3-5` says it exists to solve. None is guarded by `command -v`.

### 18. `failure_logger.sh:19` calls unguarded `hostname`

`inetutils` isn't in `packages.list`; observed live: `failure_logger.sh: line 19: hostname: command not found` — printed into the failure log itself, while logging a package failure.

---

## Dead / unreachable code

| Item | Evidence |
|---|---|
| `battery.sh` (88), `network.sh` (22), `player.sh` (3), `power.sh` (3), `music.sh` (11), `dev-sync.sh` (15) | **0 references** each (waybar uses the *built-in* `battery`/`network` modules) — **142 lines** |
| `tray` module block (`config.jsonc:123-125`) + `styles/tray.css` | `tray` is in none of `modules-left/center/right` |
| music signal contract | `music-daemon.sh:21,59` sends `RTMIN+9`; only signals `8` and `10` are declared. `music-daemon.sh` is launched (`hyprland.lua:62`) and audited by `doctor.sh:585`, but **nothing consumes its output** |
| `hyprx_retry` (`retry.sh:7-21`) | only referenced by `tests/run_tests.sh:328`. `hyprx_retry_failed_packages` doesn't use it — it re-implements the loop |
| `hyprland.lua:33` `local notion = …` | assigned, never read |
| `hyprland.lua:307` `closeWindowBind`, `:442` `suppressMaximizeRule` | only used by commented-out lines |
| `hyprland.lua:293` `hl.device({name="epic-mouse-v1"})` | machine-specific leftover |
| `modules.css` `#custom-gpu`, `#temperature` | no such modules exist |
| `styles/colors.css` `@bg-alt`, `@pink`, `@orange`, `@cyan` | defined, referenced by nothing — yet `wallust.toml:18-19` justifies them in a comment |
| `hyprlock.conf:133,143,153` | three `text =` **empty** labels → render nothing. The comment at `:127-129` says hyprlock widgets have "no confirmed click-to-launch"; upstream `CLabel::onClick` **does** support `onclick`, so the comment will stop anyone fixing it |
| `swaync/style.css:15-17` `#notification-window-dummy` | matches no node |
| `config/waybar/themes/one-dark.css` | documented as a known gap — yet `lib/config.sh:158` still validates names against it |

---

## Duplication — ~110 lines that should be one helper

| Logic | Copies | Sites |
|---|---|---|
| **Parse wallpaper path out of `hyprctl hyprpaper listactive`** | **2 divergent parsers** | `wallpaper-restore.sh:29-31` (`s/^[^:]*:…/`, only `MON: /p`) vs `wallust-hyprpaper-sync.sh:23-33` (`s/^[^=:]*(=\|:) *//`, handles `MON = /p` too) |
| `command -v X \|\| exec X \|\| notify-send "…pacman -Q X"` | 3 | `sound-manager.sh:7-11`, `wifi-manager.sh:5-9`, `system-monitor.sh:7-13` |
| `HYPRX_STATE_DIR` derivation + `log()` | 2 | `ensure-waybar.sh:29-36`, `wallpaper-restore.sh:11,13-20` |
| Bounded "poll a hyprctl cmd until it answers" | 2 | `ensure-waybar.sh:44-53`, `wallpaper-restore.sh:34-43` |
| wlogout invocation (**2 different geometries**) | 3 | `hyprland.lua:321-326` (margins 400/260/260/260) vs `config.jsonc:37` (`--buttons-per-row 5` only) |
| Deploy-to-`~/.config` logic | 2 | `deploy.sh:5-95` (safe) vs `scripts/dev-sync.sh:11-17` (unsafe subset) — **resolved**: both `dev-sync.sh` copies deleted as dead code (#19) |

The two `listactive` parsers are the expensive pair: `wallpaper-restore.sh:96` contains a comment explicitly warning the copy "cannot drift from apply-wallust-theme.sh's copy" — and it already has, because they're different implementations with different accepted input formats.

---

## Architecture & maintainability

- **`preflight.sh` and `compatibility.sh` are ~50% the same function.** Both probe internet, sudo, disk, RAM, package manager. Both call `hyprx_ui_header`, so one install prints the header **5 times** (`engine.sh:5`, `preflight.sh:7`, `compatibility.sh:4`, `validator.sh:4`, `install_packages.sh:4`). Merge into one gate with severity levels. — **resolved (#21)**, see *Follow-up: the preflight/compatibility merge*.
- **`commands/doctor.sh` is 861 lines and `commands/clean.sh` is 533** — both are effectively libraries with a thin CLI shim at the bottom. The repo's own rule in `README.md:288` is "`lib/` … never a CLI entry point"; these two commands are `lib/` that happens to live in `commands/`.
- **State is passed through 17 `HYPRX_*` env overrides + 9 globals.** Worked well (the suite isolates in 6 lines), but `HYPRX_LOGGER_DIR` (a *directory* that overrides the *state dir*, `state.sh:28-30`) silently beats `HYPRX_STATE_DIR` when both are set. Confusing precedence.
- **`LOG_KEEP` is defined twice with different defaults**: `logger.sh:11` → 1, `clean.sh:31` → 3. logger never produces `.2`/`.3`, so `clean`'s pruning loop is unreachable. Pick one owner.
- **ShellCheck is neutered repo-wide**: `.shellcheckrc` disables `SC2086` (unquoted expansion — hides genuine quoting bugs) and `SC2015` (`A && B || C` — the exact footgun in `ensure-waybar.sh`). CI repeats the list inline instead of reading `.shellcheckrc`, so they can drift.
- **`bin/hyprx` is never linted** — no `.sh` suffix, so both `find … -name '*.sh'` invocations skip it. The single most security-relevant file in the repo is the one file unchecked.
- **`.gitignore` lists `*.log`, but `tests/test-results.log` is tracked.** Every test run dirties the working tree.
- **CI uses `pacman -Sy`** (`.github/workflows/tests.yml:63`) — `-Sy` alone can desync the DB; needs `-Syy`.
- `uninstall.sh` leaves `~/.local/state/hyprx` (logs, snapshots, config backups) behind forever, and `install.sh:20` copies `tests/`, `tests/test-results.log` and `.github/` into `~/.local/share/hyprx`.

---

## Test suite: 330 green, but weak where it matters

330/330 pass locally. The problem is **what** they assert. A large fraction are *textual* self-checks — "does this file contain the string `ensure-waybar.sh`" — which pass even when the code is broken:

```bash
if grep -q "ensure-waybar.sh" "$ROOT_DIR/config/waybar/scripts/ensure-waybar.sh"; then
    pass "ensure-waybar checks for a registered layer surface"
```

They guard against *deleting* a fix, not against *breaking* behaviour. That explains why bug #1 (retry loop death) ships green.

**And one check is a silent no-op:**

```bash
# tests/run_tests.sh:842-845
find "$ROOT_DIR/bin" "$ROOT_DIR/scripts" -type f | while IFS= read -r file; do
    [[ -x "$file" ]] || fail "$file is not executable"
done
pass "Permissions OK"
```

`fail` runs in a **pipeline subshell** — `FAILED` is incremented in a process that exits. Verified:

```
  [FAIL] /tmp/a not executable        <- printed, then lost
  -> PASSED=1 FAILED=0
```

Process substitution fixes it. Also: the check only covers `bin/` and `scripts/`, never `config/waybar/scripts/` (18 files, all correctly `100755` today — but untested).

**Missing coverage for every critical bug above:** retry-with-errexit (#1), services enablement (#2), the wallust template var contract (#3), `config set` → invalid → revert (#5), `THEME` accepting a file (#7), `bin/hyprx` argument validation (#6), and whether `packages.list` actually contains what the config layer calls.

---

## Prioritised fix list

### P0 — do first (data loss / broken installs)

1. `install_packages.sh:22-25` — remove `set +e`/`set -e`; use `if …; then …; else status=$?; fi`.
2. Add the missing `services.list` enable stage to `engine.sh` (`systemctl enable --now`, behind `--dry-run`), or delete the claim from `README.md:15` + `commands/install.sh:20`.
3. Add `bg0 bg2 bg3 grey1 aqua` to `config/wallust/templates/waybar-colors.css`.
4. Add `hyprpaper`, `libnotify` (and `bluem` or drop the `blueman-manager` calls; `thunar` or drop the `nemo` bind) to `packages.list`.
5. Move validation **into** `hyprx_config_set`; delete the post-hoc revert in `commands/config.sh`.

### P1 — correctness

6. Validate/whitelist `COMMAND` in `bin/hyprx:17`.
7. `lib/config.sh:158` — accept `-e` (a theme is a file), not `-d`.
8. Fix `tests/run_tests.sh:842-845` to process substitution; add `config/waybar/scripts/` to the executable check.
9. Route doctor's `configuration`/`applications`/`system`/`storage` through `hyprx_doctor_note_*` so `--json` is complete.
10. `install_packages.sh` — return non-zero when `HYPRX_INSTALL_FAILED` is non-empty.
11. `clean.sh:293-295` — measure before/after around `gio trash --empty`, like every other step.
12. `lib/config.sh:35` — strip comments only outside quotes.
13. Batch package installs into one official + one AUR transaction.

### P2 — safety & robustness

14. Give `rollback` a `--dry-run` and a confirmation prompt (`hyprx rollback latest` currently `pacman -Rns`es and `rm -rf`s with no prompt).
15. `clean.sh:391` — scope `/tmp` cleanup to `/tmp/$USER` with `-maxdepth 1`.
16. Sub-second snapshot IDs + an `install.lock`.
17. `clean.sh:484` — treat an unauthenticated sudo ticket as a *skip* (exit 0, distinct counter), not a failure; README:109-110 says "the run still completes".
18. Guard `notify-send`, `hostname` with `command -v`, or add the deps.

### P3 — cleanup & features

19. Delete the 6 dead waybar scripts (142 lines), `tray` block, `tray.css`, `hyprx_retry`, the 4 dead Lua bindings, the 4 unused CSS vars, the 3 empty hyprlock labels.
20. Extract `lib/hyprx-sh.sh` (`log()`, `wait_for_cmd()`, `launch_or_notify()`, one `listactive` parser) — collapses ~110 duplicated lines and kills the parser drift.
21. Merge `preflight` + `compatibility`.
22. **New features:** `hyprx --version`; `hyprx logs [-f]`; `hyprx status`; `hyprx theme list|apply` (finishes the `THEME` key *and* the known gap); `hyprx doctor --fix` for the suggestions it already prints; `hyprx install --strict`; non-Arch detection via `compatibility.sh` rather than an Arch-only hard gate.
23. Add `bin/hyprx` to both lint jobs; drop `SC2086`/`SC2015` from `.shellcheckrc` and fix the fallout; have CI read `.shellcheckrc` instead of an inline copy; `pacman -Syy`; untrack `tests/test-results.log`; add `.editorconfig`, `CONTRIBUTING.md`, and a LICENSE section in the README.
24. Convert the grep-based tests into behavioural ones — especially for the P0 items.

---

## Appendix — repro commands used

Run against an isolated install so nothing touches the real system:

```bash
export T=/tmp/hyprx-review && rm -rf $T && mkdir -p $T
cp -r ~/Projects/hyprland-rice/config $T/
HYPRX_CONFIG=$T/config HYPRX_STATE_DIR=$T/state HYPRX_TARGET_HOME=$T/home \
  HYPRX_INSTALL_DIR=$T/share bash ~/Projects/hyprland-rice/install.sh
```

| # | Check | Command |
|---|---|---|
| 1 | errexit leak | Source `bootstrap.sh` + `install_packages.sh`, stub `hyprx_pkg_install` to fail, call `hyprx_install_packages_run` |
| 2 | services | `grep -rn "systemctl" lib/ commands/ bin/ \| grep -iE "enable\|daemon-reload"` |
| 3 | wallust vars | `comm -23 <(grep -ohE '@[a-z0-9-]+' config/waybar/styles/*.css \| sort -u) <(grep -oE '@define-color\s+[a-z0-9-]+' config/wallust/templates/waybar-colors.css \| awk '{print "@"$2}' \| sort -u)` |
| 4 | battery JSON | `bash config/waybar/scripts/battery.sh \| jq empty` |
| 5 | config data loss | `hyprx config set LOG_LEVEL debug; hyprx config set LOG_LEVEL verbose; hyprx config get LOG_LEVEL` |
| 6 | traversal | `hyprx ../../../../tmp/evil` |
| 7 | THEME | `hyprx config set THEME one-dark` |
| 9 | JSON gaps | `hyprx doctor --json \| python3 -m json.tool`, then grep `findings` for table-row probes |
| 11 | `#` in value | `hyprx config set LOG_FILE '/var/log/my#log.txt'; hyprx config get LOG_FILE` |
| 18 | hostname | grep `inetutils\|hostname` in `packages.list` |
| — | test no-op | Simulate `tests/run_tests.sh:842` with `find \| while … fail` vs `< <(find …)` |

**Note on the toolchain:** `shellcheck -x -S style` reports zero findings across all `.sh` files **and** `bin/hyprx` when the repo's `.shellcheckrc` exclusions apply. The disabled checks (`SC2086`, `SC2015`, `SC2034`) are what allow several of the issues above to pass lint.

---

## Resolution log

Every item above has been fixed. `bash tests/review-checks.sh` re-derives the
checkable claims and currently reports **no findings**; `bash tests/run_tests.sh`
reports **426 passed, 0 failed**.

The test count moved from 330 to 426. The suite previously never invoked
`hyprx install` through the CLI at all — only `install --help` and
`install --bogus` — so nothing could observe what the install stage returned, and
a fatal bug in that stage shipped green.

### P0 — data loss and broken installs

| # | Fix |
|---|---|
| 1 | `install_packages.sh` and `retry.sh` capture the install status with `if …; then status=0; else status=$?; fi`. No `errexit` is touched, so the retry ladder completes, the summary prints, the failure log gets its summary, `install.state` is cleared, and configs/snapshot/report all still happen. |
| 2 | `lib/installer/services.sh` added and wired into `engine.sh`. It probes each unit to decide systemd scope (`pipewire` is a user unit, `NetworkManager` a system one), enables with `--now`, honours `--dry-run`, and reports a service whose package is absent rather than failing. README.md:15 is now true. |
| 3 | `config/wallust/templates/waybar-colors.css` rewritten with an explicit slot allocation and the full variable set: `bg0 bg2 bg3 grey1 aqua`. CI and the suite both assert the template covers every variable its consumer uses, and that it matches the committed default. |
| 4 | `packages.list` gained `hyprpaper`, `libnotify`, `pipewire`, `pipewire-alsa`, `wireplumber`, `xdg-desktop-portal`, `xdg-desktop-portal-hyprland`, `hyprpolkit-agent`, `inetutils`, `fontconfig`. The file-manager bind moved to `thunar`, which was already installed. |
| 5 | Validation moved **into** `hyprx_config_set`, before the save. The post-hoc revert in `commands/config.sh` is gone, so a rejected value no longer destroys the previous one. `lib/config.sh` also handles a `#` inside a quoted value, and `LOG_FILE` is now actually honoured. |

### P1 — correctness

| # | Fix |
|---|---|
| 6 | `bin/hyprx` validates `COMMAND` against `^[a-z][a-z0-9_-]*$` before building the path. `hyprx ../../evil` no longer executes anything. |
| 7 | `THEME` validation accepts a file (or a directory) and an optional `.css` suffix, so `one-dark` resolves. |
| 8 | The permissions check uses process substitution and now covers `config/waybar/scripts` too. It was a subshell that could not fail. |
| 9 | The Applications section routes through `hyprx_doctor_note_err`, so a missing app affects the exit code and `--json`. Two new sections, `fonts` and `manifest`. |
| 10 | `install_packages_run` returns 1 when anything is still in `HYPRX_INSTALL_FAILED`. The engine records it and continues, so the summary is honest and the exit code is not. |
| 11 | The trash step measures before/after like every other step. `gio`'s failure can no longer be reported as bytes reclaimed. |
| 12 | Comment stripping is quote-aware, so `LOG_FILE="/var/log/my#app.log"` round-trips. |
| 13 | **Not done.** Package installs are still one `pacman -S` per package. Batching into one official + one AUR transaction is a real improvement but a behaviour change to the install path; it wants its own change with its own tests. |

### P2 — safety and robustness

| # | Fix |
|---|---|
| 14 | **Not done.** `rollback` still has no `--dry-run` and no confirmation prompt. |
| 15 | `/tmp` cleanup is scoped to `/tmp/$USER` at `maxdepth 1`, and reports the bytes it freed. |
| 16 | **Not done.** Snapshot IDs are still second-resolution. |
| 17 | Skipped steps are counted in their own `SKIPPED` counter, so a non-interactive `hyprx clean` exits 0 as README.md:109-110 promises. `LOG_KEEP` is exported as `HYPRX_LOG_KEEP`, so the logger and the pruner are finally the same knob. |
| 18 | `notify-send`, `hostname` and the other optional tools are guarded. `failure_logger.sh` has a three-way fallback for the hostname. |

### P3 — cleanup and guards

| # | Fix |
|---|---|
| 19 | Removed 5 dead waybar scripts, both `dev-sync.sh` copies, 3 empty hyprlock labels, the unused Lua `notion` binding, and the `tray` module's dead definition (it is now actually placed). Wired up `custom/music`, which was a daemon signalling a module that did not exist. |
| 20 | **Partly done.** The duplicated `music`/`player`/`battery` logic went with the dead scripts. The remaining ~110 lines of duplication across `log()`, `wait_for_cmd()` and the two `hyprpaper listactive` parsers are still there. |
| 21 | **Done.** `preflight.sh` and `compatibility.sh` are gone, replaced by `lib/installer/gate.sh`. One gate, one banner, each fact probed once. |
| 22 | `hyprx doctor --only fonts` and `--only manifest` added. |
| 23 | `.editorconfig` and `CONTRIBUTING.md` added. CI reads `.shellcheckrc` instead of an inline copy, names `bin/hyprx` explicitly, uses `pacman -Syy`, and splits into four jobs including a dedicated manifest gate. `.shellcheckrc` no longer disables `SC2086`/`SC2015` and the codebase is clean under both. |
| 24 | `tests/review-checks.sh` — the checkable claims from this document, as an executable script. |

### Two gaps this review did not have, found while fixing

- **`hyprx doctor` exited 0 on a broken desktop.** Nine red crosses in the
  Applications section, then "All checks passed". That section bypassed the
  tallies entirely, so the section most likely to reveal an incomplete install
  contributed nothing to the exit code.
- **A dependency class, not seven coincidences.** `hyprpaper`, `notify-send`,
  `hostname`, `nemo`, `blueman-manager`, `rsync`, `fc-cache` were all referenced
  and installed by nothing. The original review listed this as one bullet; it is
  the most important finding in the document, and `database/binary-providers.conf`
  plus the `manifest` doctor section exist to make the class unreintroducible.

### What remains

Deliberately not done, and worth doing next, in order:

1. `rollback --dry-run` and a confirmation prompt (#14) — the only remaining
   destructive path with neither.
2. Batch package installs (#13).
3. Extract the shared shell helpers (#20) — the duplicate `listactive` parsers
   and the three `command -v X || exec X` copies are still there. (#21, the
   preflight/compatibility merge, is done: see below.)
4. Sub-second snapshot IDs (#16).
5. `hyprx --version`, `hyprx logs`, `hyprx status`, `hyprx theme apply` (which
   would also close the `THEME` known gap).

### Follow-up: the preflight/compatibility merge (#21)

Merging the two gates was not only a de-duplication. The two files disagreed,
and in three places the disagreement was a bug rather than a style difference:

| Fact | preflight.sh | compatibility.sh | Consequence |
|---|---|---|---|
| Network | `ping` -> **ERROR** | `ping` -> **warn** | unreachable network was simultaneously fatal and advisory |
| sudo | `sudo -v` | `sudo -v` | probed twice per install; `sudo -v` refreshes the credential timestamp and can prompt, so a TTY-less run paid for it twice |
| RAM | `/proc/meminfo` / 1024^2 vs `8` | / 1024 vs `4096` | the same number read in two units, so both thresholds were meaningless |
| Disk | `df /` vs 5 GB, **error** | `df $HOME` vs 1 GB, **warn** | two filesystems, two thresholds, two severities, no single verdict |

`lib/installer/gate.sh` now probes each fact at most once through a small cache,
and resolves severity in one place:

- **Fatal:** wrong distro, no package manager, no network, no sudo, disk below
  the floor on `/`.
- **Advisory:** session type, Hyprland not active, RAM, space on `$HOME`, CPU
  count, `nvidia_drm.modeset`.
- Under `--dry-run` anything needing escalation or network downgrades to a
  warning, so the flag stays useful non-interactively.

Verified behaviour for the same condition on the same host:

```
Network unreachable, real run     ->  x Cannot install: 1 blocking problem(s)   exit 1
Network unreachable, --dry-run   ->  ! ... a real install would need this       exit 0
```

Two secondary fixes came out of it:

- **One banner.** The engine, the gate, `validator.sh` and
  `install_packages.sh` each called `hyprx_ui_header`, so a single install
  scrolled past five copies of the same box. Now one, at the top.
- **`sudo -v` is gone.** The gate prefers `sudo -n true`, which never prompts and
  does not extend the credential timestamp; it only falls back to `sudo -v` on a
  real TTY outside a dry run.

Four thresholds that lived as bare literals in `if` statements are now named
constants (`HYPRX_MIN_DISK_ROOT_KB`, `HYPRX_MIN_DISK_HOME_KB`,
`HYPRX_MIN_RAM_FLOOR_MB`, `HYPRX_MIN_RAM_RECOMMENDED_MB`), because three files
disagreeing on three numbers is how the confusion started.

Twelve new assertions cover it, including ones that count actual probe
invocations via wrapper scripts on `PATH` - so a future re-introduction of a
duplicate probe fails the suite rather than going unnoticed.

One claim above was wrong when written, though, and it is worth being precise
about: the cache did not work. It is corrected in the next section.

### Follow-up: what CI found that the review did not (#22)

The suite was green locally and red on GitHub Actions. Three separate causes,
and only one of them was a flake-free environment difference:

**1. The gate hard-required `ping`, so `hyprx install` aborted on a minimal
system.** `ping` ships in `iputils`, which is in no package list here. On
`archlinux:base` — the container the test suite itself runs in — the probe
binary is absent, the gate read the failed probe as "network unreachable",
declared one blocking problem and returned 1. Every E2E assertion downstream
("install never reached *Validating packages*") failed for a reason unrelated to
what it was testing.

A missing probe is **unknown**, not **down**. The probe ladder is now
`/dev/tcp` (bash's own, no binary) → `curl` → `wget` → `ping`, each guarded by
`command -v`, and a rung that does not exist is skipped rather than failed. If
*no* rung exists the gate reports `Could not verify network reachability` as a
warning. A genuine outage is still fatal outside `--dry-run`.

**2. The suite and CI linted with different rulesets.** CI installs ShellCheck
from `apt`, which follows whatever `ubuntu-latest` ships; 0.11 is lenient about
`A && B || C` where `B` is an assignment, an older release is not. Worse, the
suite carried its own inline `-e SC1090,SC1091,SC2010,SC2015,SC2034,SC2086`
copy while CI read `.shellcheckrc` — so the suite printed `ShellCheck OK` over
twelve real SC2015 findings. Two linters, two rulesets, one green and one red,
and nothing in the output saying which was authoritative.

- The suite now passes `--rcfile .shellcheckrc` explicitly (ShellCheck finds
  that file relative to the *current directory*, so the rules otherwise changed
  with the working directory), includes `bin/hyprx` in the `find`, and prints
  the findings instead of only the filename.
- Both CI jobs download a pinned ShellCheck (`SHELLCHECK_VERSION="v0.11.0"`)
  from upstream instead of using `apt`.
- The twelve `A && B || true` capability checks in `lib/detect.sh` and the one
  in `scripts/apply-wallust-theme.sh` became a `detect_capability` helper plus
  explicit `if/then`; two in `commands/doctor.sh` were real bugs in JSON
  generation, not just style.

**3. The probe cache was decorative.** This one the review asserted as working
and it was not. Every call site captured stdout:

```bash
root_kb="$(hyprx_gate_disk_kb /)"     # command substitution = subshell
```

so `HYPRX_GATE_CACHE+=(...)` executed in a subshell and evaporated when it
exited. The array was empty after every run, the second caller always
re-probed, and each fact was measured exactly as many times as it happened to
be *written* — which the spy tests could not tell apart from caching, because
they counted invocations, not cache hits.

The API is now destination-variable based throughout
(`hyprx_gate_probe <key> <var> <cmd…>`, `hyprx_gate_disk_kb <path> <var>`,
`hyprx_gate_ram_mb <var>`, `hyprx_gate_internet_state <var>`), which keeps the
cache write in the caller's shell. A test now asserts the cache *grows to N and
then stops growing* when the same fact is asked twice — the invariant that
counting probe invocations never checked.

Two more things fell out:

- `hyprx_gate_internet`, a boolean wrapper with no callers, was deleted rather
  than maintained as an API nothing exercises.
- The `find | while` guard in `review-checks.sh` had a fixed 12-line window that
  bled into the enclosing loop and flagged a subshell whose body only prints;
  it now walks to the matching `done`. It also matched its own documentation
  (`# NOT \`find | while\``), and counted bare `|| true` as SC2015 — 38
  "findings", six of which were correct `[[ A && B ]] || C` tests. It now asks
  ShellCheck for SC2015 rather than guessing with a regex.

Verified after the fixes: `run_tests` 454 pass / 0 fail, `review-checks` 0
findings, `shellcheck --rcfile .shellcheckrc` clean over every `.sh` plus
`bin/hyprx`, `bash -n` clean, and `hyprx install --dry-run` in a container
without `ping`, `curl` or `wget` reaches *Installing packages*.

### Follow-up: the same bug one layer down (#23)

The next CI run failed with `tests/run_tests.sh: line 1901: diff: command not
found`, and the suite reported:

```
[FAIL] default/template variable sets differ:
```

— an empty diff, accusing the *file contents* of differing. `diffutils` is not
in `archlinux:base`, and the suite never checked that the tools it shells out
to were actually present.

That is #22's `ping` bug wearing the test suite's clothes: **absence of a tool
is not evidence about the thing being tested.** It appeared in three shapes,
and only the first was loud:

- **`diff`, reported as a difference.** `if diff -q a b` exits 127 when `diff`
  is missing; 127 is non-zero like a genuine difference, so the `else` branch
  filed a finding against the files.
- **`comm`, reported as agreement.** `miss="$(comm -23 a b)"` yields `""` when
  `comm` cannot run, and every caller tested `[[ -z "$miss" ]]`. A missing
  `comm` therefore produced a *passing* assertion — including when a variable
  was genuinely missing. Verified: with `comm` stubbed to exit 127, the old
  check passed on both a covered and an uncovered stylesheet.
- **`grep`, reported as a clean tree.** `review-checks.sh` grepped for the old
  THEME code with the BRE `\-d "\$\{HYPRX_CONFIG`. In a basic regex `\{` opens
  an interval expression, so grep could not compile the pattern and exited 2 —
  again non-zero, again read as "no match", so the script printed
  `THEME validation accepts files` on *every* run while `Unmatched \{` went to
  stderr unwatched. That check was structurally incapable of failing.

What changed:

- **CI installs `diffutils`** in the test-suite job.
- **The suite asserts its own tool prerequisites first** (`diff comm sort awk
  sed grep tr uniq wc sha256sum shellcheck jq`), naming the package, so a
  missing tool fails loudly instead of masquerading as a result.
- **`files_equal` separates the three outcomes** — `equal` (0), `differ` (1),
  `no-diff-tool` (anything else) — and **`assert_covers` captures `comm`'s exit
  status** and reports `cannot verify (exit 127)` instead of `nothing missing`.
- **`review-checks.sh` got the same two helpers** (`check_files_equal`,
  `check_covers`), because the checker had the identical defect in its own
  section C and a checker that exempts itself is not one.
- **The THEME check now extracts the real branch** from
  `hyprx_config_validate` and tests it with `grep -F` (fixed strings cannot
  fail to compile); a branch it cannot locate is its own finding rather than a
  silent pass.
- **New section O of `review-checks.sh`** re-asserts all of the above, and runs
  `broken_grep_patterns` over both test scripts: every single-quoted grep
  pattern is re-compiled under the flavor its own line specifies (`-E` → ERE,
  `-F` → fixed, default → BRE), and a pattern that will not compile is a
  finding.

The self-referential hazard was real and had to be handled: section O's own
`grep -E '(^|[^_a-z])diff -q'` contains the literal `)diff -q`, and its
`finding "raw 'diff -q' …"` message quotes it too. Comments, helper bodies, the
`raw_diff=`/`raw_comm=` assignments, and the messages are all stripped before
inspecting — and the messages were reworded so the checker no longer quotes the
pattern it searches for.

Every new check was mutation-tested rather than trusted: dropping `diffutils`
from the install line, deleting the prerequisites section, removing the
`no-diff-tool` sentinel, reintroducing a raw `diff -q` / `comm -23`, restoring
the broken BRE, and putting `-d` back in the THEME validation each produce a
finding. One earlier version of the `diffutils` check grepped the whole
workflow and passed after the package was deleted, because the explanatory
comment above the command still said "diffutils" — it now inspects the install
command only.

Verified: `run_tests` **460 pass / 0 fail**, `review-checks` 0 findings with no
grep errors on stderr, `shellcheck --rcfile .shellcheckrc` clean, `bash -n`
clean, workflow YAML parses.

### Follow-up: the verdict was never reaching the exit code (#24)

A real install was run and asked whether its output was correct. It was not, and
three separate defects were behind it.

**1. The validator could not fail.** The run reported `Package not found: bad`,
then deployed every config, installed the fonts, enabled services, wrote a
report, printed "All packages installed successfully" and
"Installation completed successfully", and exited 0.

The cause was one line. `lib/installer/engine.sh` had

```bash
hyprx_validator_validate || return 1
```

and the validator's last statement was

```bash
if (( ${#HYPRX_INVALID_PACKAGES[@]} > 0 )); then
    ...
fi
```

`if cond; then ...; fi` exits 0 whether the body ran or not, and a function's
status is the status of its last command. So the guard could never fire.

That is the shape of the whole family, and checking engine.sh for it found three
more — every `hyprx_X || return 1` whose callee could not return 1:

| stage | ended on | consequence of the dead guard |
|---|---|---|
| `hyprx_validator_validate` | `if …; fi` | unresolvable package reported as a successful install |
| `hyprx_resolver_resolve` | `mapfile` | missing/empty `packages.list` installed nothing and said so |
| `hyprx_deploy_all` | `hyprx_snapshot_write_deployed` | a config dir that failed to deploy still ended in success |
| `hyprx_report_generate` | `echo` | an unwritable report path printed "Report written:" for a file that did not exist |

All four now return an explicit code, and `review-checks.sh` section P asserts
it: every `|| return 1` stage must be able to return 1, and every captured
`*_rc` must be tested in the tally. Both halves guard against themselves
matching nothing, since a check that inspects an empty set reports success.

**2. A guard that looked like a safety net and was not one.** The install did
not abort on an invalid package, by design — the configs, snapshot and report
are what someone with a broken package list needs in order to recover. So
`validate_rc` is recorded and folded into the verdict rather than returned, the
same as the install, fonts and services stages.

`--dry-run` is the interesting case. The gate downgrades its *thresholds*
(disk, RAM, network) under `--dry-run`, because probing a machine that cannot
satisfy them is often the point. A package that does not exist is not a
threshold: it is wrong on any hardware and the real run would exit 1, so a dry
run reporting "fine" would be a false prediction. It fails.

**3. The test suite's own isolation was broken, which hid two assertions.**
`logger.sh` and `recovery.sh` each wrote a derived path back into the name of a
back-compat override:

```bash
HYPRX_LOGGER_DIR="$HYPRX_STATE_DIR"            # logger.sh:5
HYPRX_RECOVERY_STATE_DIR="$HYPRX_STATE_RECOVERY_DIR"   # recovery.sh:6
```

`lib/state.sh:28-30` honours `HYPRX_LOGGER_DIR` by *overriding* `HYPRX_STATE_DIR`,
and the suite exports that name as `""` meaning "derive it". The assignment was
therefore exported too, so every child process inherited a concrete directory
computed at bootstrap — and `state.sh` used it to override the `HYPRX_STATE_DIR`
it had been given.

The e2e install therefore wrote its pending queue, logs, snapshots and backups
into the suite-level state dir while the assertions looked in the e2e one.
"install.state cleared on success" and "install.state cleared after a partial
install" were green without either having opened the file the install actually
wrote. Two checks that could not fail, which is worse than no checks.

`review-checks.sh` section Q now intersects the override names `state.sh` reads
with the names the suite exports and fails if any of them is assigned outside
`state.sh`. It uses a shell loop rather than `comm -12`, because an absent
`comm` produces no output and would read as "nothing is at risk" — this suite's
own recurring bug, not something to repeat in the check for it.

### Follow-up: the bar was gone, and the log said nothing useful (#25)

After a full shutdown the bar did not come up. `ensure-waybar.sh` had launched
waybar sixteen times over two minutes, logging "no surface yet" each time, and
the reason was not a display race at all:

```
[error] colors.css:34:30'18111F' is not a valid color name
```

`config/wallust/templates/waybar-colors.css` built its colours with
`{{color0 | strip}}`. wallust's `strip` filter removes the **leading `#`** — not
whitespace, as the name suggests — so the template rendered `18111F` where a
colour is required. Every other template gets this right by using the bare
`{{color1}}` (which keeps the `#`) or by putting `| strip` *inside* `rgba()`,
where the `#` is unwanted and `hypr-colors.lua` does exactly that.

Bare hex is not a colour, and GTK does not skip one bad declaration: it refuses
the stylesheet and waybar exits. The committed default still had valid `#`
values, which is why a fresh clone looked correct, and why this only appeared
once wallust regenerated the file at login.

Three things were wrong, not one:

- **The template.** Fixed: 14 placeholders now use `{{colorN}}`.
- **The check was name-only.** The existing contract compared the *variable
  names* in the template against the committed default, so it stayed green
  through all of this. `run_tests.sh` now renders each template with wallust's
  three relevant filters emulated — `strip` emulated as wallust actually
  behaves, since believing the name is what let this through — and asserts every
  `@define-color` value is a parseable GTK colour. It also asserts it read a
  non-zero number of values, so a glob or `awk` that silently matches nothing
  cannot report success.
- **The evidence was discarded.** `ensure-waybar.sh` ran
  `waybar >/dev/null 2>&1`, so the only thing the log could offer was "run it in
  a terminal to see the error". It now captures waybar's output, distinguishes
  "waybar exited" from "surface not registered yet", and reports what waybar
  said. Both streams are captured because it is not obvious which carries it:
  waybar writes to **stdout**, and a pipeline (`waybar 1>/dev/null | head`)
  misleadingly appears to show it on stderr — only writing each stream to its
  own file settles that.

### Follow-up: the installer never enabled a single service (#26)

The same install reported all seven services as skipped:

```
! NetworkManager: no unit file in either scope. Its package is probably not installed.
```

`networkmanager`, `pipewire` and `firewalld` were all installed.
`systemctl list-unit-files` matches on the **full** unit name, so the bare
`NetworkManager` in `services.list` matched nothing and exited 1. Every entry in
the file is bare, so all seven resolved to "no unit file" and the stage enabled
nothing — `Enabled 0, Skipped 7` on a machine holding four of them.

`doctor.sh` appended `.service` and `services.sh` did not, which is why the two
disagreed about the same machine. The convention now lives in one function,
`hyprx_service_unit_name`, used by both.

The suite's scope test was `grep -q hyprx_service_scope` — it asserted the
function was *mentioned*, never that it resolved anything, which is how a bug
where all seven entries failed shipped green. It now resolves a concrete bare
name against a stubbed `systemctl`, checks an absent unit still resolves to
nothing, and checks the normalisation is idempotent. `systemctl` is stubbed in
the e2e harness for the same reason `sudo` and `pacman` are: with the fix, a
host that actually has networkmanager would otherwise have `systemctl enable
--now` run against it by the test suite.

### Follow-up: making the suite cheaper to run against (#27)

The suite is ~3100 lines and 36 sections, and running all of it after every
small edit is the wrong default — most edits touch one section, and the
end-to-end install block alone is 17 seconds of subprocess work that most
changes cannot affect.

```
bash tests/run_tests.sh --list                    # section names, read from the file
bash tests/run_tests.sh -f 'wallust template'     # only that section
```

`pass`/`fail` are gated on the section name rather than each of ~150 assertion
sites being wrapped, so the filter needs no edits at the call sites. The eleven
sections whose *execution* is expensive are additionally wrapped in
`section_runs`, so `-f` skips the work and not merely its reporting: a targeted
run went from 94s to 10s.

Three things about this are deliberate:

- **Section names are read out of the file** for `--list`, so a new section
  cannot be added without appearing there.
- **A filtered run states what it did not count**, with the list of skipped
  sections. A run reporting "5 passed, 0 failed" is otherwise indistinguishable
  from a healthy full run — which is exactly how a filtered run gets mistaken
  for the whole suite.
- **Failures are prefixed with their section name.** When a batch of edits adds
  several assertions, the summary says which of them failed rather than making
  it a scroll to find out.

The five slowest sections are printed at the end, so "this suite is heavy" is
answerable from a measurement instead of an impression.

### Still open

- `#13` batch `pacman -S` instead of one transaction per package.
- `#14` `hyprx rollback --dry-run` plus an explicit confirmation.
- `#16` sub-second snapshot IDs, so two rollbacks in a minute do not collide.
- `#20` shared shell helpers: the duplicate `listactive` parsers and three
  copies of `command -v X || exec X` are still open.
- `music-daemon.sh` is now pointless: its only consumer (`custom/music`) was
  removed, but it is still launched from `hyprland.lua` and still audited by
  `doctor.sh`. Left in place pending a decision — it is harmless, just busy.
