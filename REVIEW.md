# HyprX — Repo Assessment

> Note (2026-10-06): the suite (`tests/run_tests.sh`, 435 passing) and
> `tests/review-checks.sh` were removed — CI cost outweighed their value at
> this stage. Both survive in git history. Claims below that say "asserted" or
> "suite-asserted" describe the state while the suite existed; new features
> ship with focused tests per `tests/README.md` instead.

Every finding below was reproduced, then fixed. `bash tests/review-checks.sh`
re-derives the checkable claims and reports no findings;
`bash tests/run_tests.sh` is the gate. Findings **1–7** were severe enough to
break an install outright.

## Contents

- [Critical findings](#critical-findings)
- [Correctness findings](#correctness-findings)
- [Dead code, duplication, architecture](#dead-code-duplication-architecture)
- [Test suite](#test-suite)
- [Resolution log](#resolution-log)
- [Follow-ups](#follow-ups)
- [Still open](#still-open)

---

## Critical findings

**1. `set -e` leaked out of the install loop and killed the install.**
`install_packages.sh` used `set +e` / `status=$?` / `set -e`. `bin/hyprx` runs
with only `set -uo pipefail`, so after the *first* package attempt errexit was
globally on and the next unguarded failure — `hyprx_pkg_install` inside the
retry ladder — aborted everything. One failing package killed the retry ladder,
the summary, the failure-log summary, deploy, the snapshot and the report, and
left `install.state` behind so the *next* install resumed a phantom interrupted
one. One bad package destroyed an install already ~50 packages deep. Fixed with
`if …; then status=0; else status=$?; fi`, which leaves errexit untouched.

**2. `services.list` was never acted on — the feature did not exist.**
The file was read only by `doctor`, and nothing anywhere ran
`systemctl enable`. Yet README and `--dry-run`'s own text promised an enable
stage. Fixed by adding `lib/installer/services.sh`, wired into the engine: it
probes scope (pipewire is a *user* unit, NetworkManager a *system* one),
enables with `--now`, honours `--dry-run`, and reports an absent package
instead of failing.

**3. wallust's template dropped 5 CSS variables the bar needs.**
wallust overwrites `waybar/styles/colors.css` on the first wallpaper change. The
template defined 12 variables, the stylesheets referenced 17: `bg0`, `bg3`,
`grey1`, `bg2` and `aqua` were missing, so GTK dropped those declarations and the
bar lost module backgrounds, borders, rounded corners and two module colours. A
fresh clone looked perfect, which is why it shipped. Fixed, and the template
must now cover every variable its consumer uses *and* match the committed
default — asserted in both CI and the suite.

**4. `battery.sh` emitted invalid JSON.** `printf '…\n…'` inside a JSON string
where every peer script uses `\\n`; `jq` rejected it. Masked because the script
was dead.

**5. `hyprx config set` wrote first, validated second, then reverted to the
*default* — silent data loss.** `hyprx_config_set` performed no validation at
all; the command validated after persisting and "reverted" via `unset`, which
restores the default, not the previous value. The suite asserted the buggy
result. Fixed by validating inside `hyprx_config_set` before the save.

**6. `bin/hyprx` sourced an attacker-chosen path.** `COMMAND` from `$1` was
concatenated into a path unchecked, so `hyprx ../../../../tmp/evil` ran it —
while `deploy.sh` two directories down went to real trouble to reject `../escape`.
Fixed by validating the name and deriving the whitelist from `commands/*.sh`.

**7. `THEME` validation required a directory; the only theme is a file.**
`one-dark` was unselectable despite `hyprx.conf` advertising it. Later the
setting was wired up for real: `config set THEME <name>` copies the theme to
`waybar/themes/active.css`, which the wallust template imports. The import lives
in the template rather than the committed default because wallust regenerates
that file on every wallpaper change — an import written into the default would
be destroyed at exactly the moment the theme needs to still be applied.

## Correctness findings

| # | Finding | Status |
|---|---|---|
| 8 | Install reported success with failures (fell off the end of the summary) | fixed |
| 9 | `doctor --json` structurally incomplete, while `--only` was rejected for exactly that reason | fixed |
| 10 | `clean` claimed bytes it never freed (`gio`'s failure reported as savings) | fixed |
| 11 | A `#` inside a quoted config value was eaten as a comment | fixed, quote-aware |
| 12 | One `pacman -S` per package — ~50 sequential transactions | fixed: one transaction per source |
| 13 | AUR-only packages fail silently when `PACKAGE_MANAGER=pacman` | fixed |
| 14 | Snapshot IDs collide within the same second | fixed: nanosecond IDs |
| 15 | `clean`'s `/tmp` step had a real blast radius | fixed, scoped to `/tmp/$USER` |
| 16 | Both `dev-sync.sh` copies were broken | removed |
| 17 | Undeclared runtime dependencies (`hyprpaper`, `notify-send`, `hostname`, `fc-cache`, …) referenced but installed by nothing | fixed via `binary-providers.conf` + `doctor --only manifest` |
| 18 | `failure_logger.sh` called unguarded `hostname` | fixed, three-way fallback |

## Dead code, duplication, architecture

**Dead / unreachable.** 5 waybar scripts, both `dev-sync.sh` copies, 3 empty
hyprlock labels, an unused Lua binding, and a `tray` definition that was never
placed. Removed. Also removed later: `music.sh` (its only consumer was the
`custom/music` module), `preflight.sh` + `compatibility.sh` (merged into
`gate.sh`).

**Duplication, ~110 lines still open.** Two `hyprpaper listactive` parsers and
three copies of `command -v X || exec X`.

**Architecture.** State was passed through 17 `HYPRX_*` env overrides plus 9
globals. It works and the suite isolates in 6 lines, but the precedence was
confusing: `HYPRX_LOGGER_DIR` (a *directory*) silently beats `HYPRX_STATE_DIR`
(see Follow-up 24 — it was worse than confusing, it broke the suite).

## Test suite

It was 330 green and weak where it mattered. Three examples, all since fixed:

- It asserted `info` as the correct value of `LOG_LEVEL` — **encoding the bug**
  from finding 5 as expected behaviour.
- It never invoked `hyprx install` through the CLI at all, only `--help` and
  `--bogus`, so nothing could observe what the install stage returned. A fatal
  bug in that stage shipped green.
- The services scope test was `grep -q hyprx_service_scope` — asserting the
  function was *mentioned*, never that it resolved anything, which is how
  finding 2's successor shipped green.

The suite is 435 passing and takes `-f <regex>` to run one section.

---

## Resolution log

| # | Fix |
|---|---|
| 1 | Install status captured with `if/else`, leaving errexit untouched |
| 2 | `services.sh` added and wired into the engine |
| 3 | waybar template carries the full variable set, asserted against the default |
| 4 | `packages.list` gained the missing runtime deps; file-manager bind moved to `thunar` |
| 5 | Validation moved *into* `hyprx_config_set`, before the save; no more revert |
| 6 | `COMMAND` validated and whitelisted |
| 7 | `THEME` accepts a file, a directory and an optional `.css` |
| 8 | `install_packages_run` returns 1 when anything is still in `HYPRX_INSTALL_FAILED`; the engine records it and continues, so the summary is honest and so is the exit code |
| 9 | Applications section routes through `hyprx_doctor_note_err`; `fonts` and `manifest` sections added |
| 10 | Trash step measures before/after like every other step |
| 11 | Comment stripping is quote-aware; `LOG_FILE` is honoured |
| 12 | **Not done** — one `pacman -S` per package |
| 13 | AUR-only packages reported rather than skipped |
| 14 | **Not done** — snapshot IDs still second-resolution |
| 15 | `/tmp` cleanup scoped to `/tmp/$USER` at `maxdepth 1`, and reports bytes freed |
| 16 | `dev-sync.sh` removed |
| 17 | `database/binary-providers.conf` + `doctor --only manifest` make the class unreintroducible |
| 18 | `hostname` guarded with a three-way fallback |
| 19 | Dead scripts removed; `custom/music` wired up (later removed at the user's request) |
| 20 | **Partly done** — the `music`/`player`/`battery` duplication went with the dead scripts; ~110 lines remain |
| 21 | **Done** — `preflight.sh` + `compatibility.sh` → one `lib/installer/gate.sh`, one banner, each fact probed once |
| 22 | `doctor --only fonts` and `--only manifest` added |
| 23 | `.editorconfig` + `CONTRIBUTING.md`; CI reads `.shellcheckrc`, names `bin/hyprx`, uses `pacman -Syy`, splits into 4 jobs. `.shellcheckrc` no longer disables `SC2086`/`SC2015` |
| 24 | `tests/review-checks.sh` — this document as an executable script |

### Two gaps this review did not have, found while fixing

- **`hyprx doctor` exited 0 on a broken desktop.** Nine red crosses in
  Applications, then "All checks passed" — that section bypassed the tallies
  entirely, so the section most likely to reveal an incomplete install
  contributed nothing to the exit code.
- **A dependency class, not seven coincidences.** Seven tools were referenced and
  installed by nothing. The original review listed this as one bullet; it is the
  most important finding in the document, and `binary-providers.conf` plus the
  `manifest` section exist to make it unreintroducible.

---

## Follow-ups

Found after the fixes above, each reproduced from a real run.

**21 — CI was green locally and red on GitHub.** ShellCheck 0.11 vs the runner's
older apt build disagreed about `A && B || C`; the gate also *required* `ping`,
which the runner lacks, and its probe cache was written inside `$( )`, so the
cache never persisted. Fixed: pin ShellCheck to `v0.11.0`, pass `.shellcheckrc`
explicitly, and replace `ping` with a guarded ladder (`/dev/tcp` → `curl` →
`wget` → `ping`) with three states — `ok` / `down` / `unknown`, where unknown is
a warning and never fatal.

**22 — "absence of a tool is not evidence about the thing tested."** The same
principle as 21, one layer down, in three shapes: `diff` missing exits 127,
which is non-zero, so a missing program was reported as *the files differ*;
`comm` missing yields empty output, so a *missing variable* was reported as
*covered*; and a `grep` BRE with `\{` could not compile, exited 2, and so matched
nothing — a check that printed its success on every run. Fixed by asserting tool
prerequisites up front, splitting "cannot verify" from the two real answers, and
adding a check that re-compiles every grep pattern in both test scripts under the
flavor its own line specifies.

**23 — the same bug one layer down, again.** See 22; that is the whole entry.

**24 — the verdict never reached the exit code.** A real install printed
`Package not found: bad`, then deployed everything, wrote a report, printed
"Installation completed successfully" and exited 0. `engine.sh` had
`hyprx_validator_validate || return 1`, but the validator's last statement was
`if …; fi`, which exits 0 either way — the guard could not fire. Checking
engine.sh for the same shape found three more: `resolver` ended on `mapfile`,
`deploy_all` on `hyprx_snapshot_write_deployed`, `report_generate` on `echo`.
Each produced its own version of the same lie — a run that had not done the
thing reported that it had. All four now return an explicit code, and
`review-checks` section P asserts it. `validate_rc` is *recorded* rather than
returned, so a broken package list still gets its configs and snapshot;
`--dry-run` still downgrades the gate's thresholds but not a package that does
not exist, since that is wrong on any hardware.

**24a — the suite's own isolation was broken, hiding two assertions.**
`logger.sh` and `recovery.sh` each wrote a derived path back into the name of a
back-compat override (`HYPRX_LOGGER_DIR`, `HYPRX_RECOVERY_STATE_DIR`), and the
suite exports those names as `""` meaning "derive it". The assignment was
therefore exported, so every child inherited a concrete directory computed at
bootstrap — and `state.sh:28-30` used it to *override* the `HYPRX_STATE_DIR` it
had been given. The e2e install wrote its queue, logs and snapshots into the
suite-level dir while the assertions looked in the e2e one, so "install.state
cleared on success" and "…after a partial install" were green without either
having opened the file the install wrote. Fixed at the source; `review-checks`
section Q now intersects the overrides `state.sh` reads with the names the suite
exports and fails if any is assigned outside `state.sh` — using a shell loop, not
`comm`, because an absent `comm` reads as "nothing is at risk".

**25 — the bar was gone and the log said nothing useful.** After a reboot the
bar did not appear; `ensure-waybar.sh` had retried 16 times logging "no surface
yet". The cause was not a display race: `colors.css:34:30'18111F' is not a valid
color name`. The waybar template built colours with `{{color0 | strip}}`, and
wallust's `strip` removes the **leading `#`**, not whitespace — so it rendered
bare hex. GTK does not skip one bad declaration; it refuses the stylesheet and
waybar exits. Three defects, not one: the template (fixed), a check that compared
only variable *names* so it stayed green throughout (now renders each template
with wallust's filters emulated and asserts every value is a parseable GTK
colour — and asserts it read a non-zero number of values), and
`ensure-waybar.sh` sending waybar's output to `/dev/null` (now captured and
reported; both streams, because waybar writes to **stdout** and a pipeline
misleadingly appears to show it on stderr).

**26 — the installer never enabled a single service.** All seven services were
reported "no unit file in either scope" while networkmanager, pipewire and
firewalld were all installed. `systemctl list-unit-files` matches the *full*
unit name, and every entry in `services.list` is bare, so all seven resolved to
nothing and the stage enabled none. `doctor.sh` appended `.service` and
`services.sh` did not, which is why they disagreed about the same machine. The
convention now lives in one function used by both.

**27 — the suite was too heavy to run often.** Added `--list`, `-f REGEX`, and a
slowest-5 timing report. `pass`/`fail` are gated on the section name rather than
each of ~150 assertion sites being wrapped; the 11 expensive sections are
additionally wrapped so `-f` skips the *work*, not just the reporting — a targeted
run went from 94s to 10s. Failures are prefixed with their section, and a filtered
run prints what it did not count, so it cannot be mistaken for a full run.

**28 — a warning on stdout corrupted `doctor --json`.** `hyprx_ui_warn` and its
siblings wrote to stdout, so any diagnostic prefixed the JSON document with
`! Unknown key in hyprx.conf: NOT_A_KEY`. Invisible in a terminal, because both
streams look the same there. Diagnostics now go to stderr; stdout is reserved for
what the command actually produces.

**29 — `hyprpolkit-agent` was a typo nothing could catch.** The real package is
`hyprpolkitagent` — no hyphen. A misspelled name and a removed name are
indistinguishable from the outside: both make `pacman -Si` and `yay -Si` fail,
and validation can only report "nothing answered". Fixed by declaring the
AUR-only set in `database/aur-packages.list`; `review-checks` section A fails if
a package is neither in the official repos nor declared there. The checker had
been pinning the *wrong* name, which is why the typo survived.

**30 — the suite had two order dependencies, found by running sections alone.**
The `config` section wrote `NOT_A_KEY` into `hyprx.conf` and never restored it,
so `doctor --json` returned a document prefixed by a warning — and the JSON test
still passed in a full run because an unrelated later section happened to rewrite
the file and clear it. And `find <dir> | wc -l` aborts under `pipefail` when the
directory does not exist, killing any filtered run that skipped the section
creating it. Both fixed; CI now runs every section in isolation.

**31 — `music-daemon.sh` was a daemon writing to nothing.** Its only consumer was
the `custom/music` bar module, which was removed; it was still launched every
login and still audited by `doctor`. Deleted, with its autostart line and audit
row.

**32 — the two `hyprpaper listactive` parsers disagreed about the format.** One
handled `MONITOR:` and the other also handled `MONITOR =` and a nameless
fallback. The stricter one silently returned nothing on a build printing the
other form, which looks exactly like "no wallpaper is set" — so colour
regeneration never fired and the rice kept the colours of a wallpaper that was no
longer there. Now one parser in `lib/wallpaper.sh`.

**33 — the state override names shadowed the derived ones.** `HYPRX_STATE_SNAPSHOT_DIR`
(derived) and `HYPRX_SNAPSHOT_DIR` (override) differ by one word, and the
override silently wins. Every override is now `<DERIVED>_OVERRIDE`, so the
relationship is visible at the call site. This also removed the last instance of
the write-back-into-an-override pattern from follow-up 24a.

**34 — `hyprx wallpaper`.** Setting a wallpaper used to be three tools and a
daemon, and doing it by hand meant the colour regeneration could be missed —
which is invisible, because the rice just keeps the colours of a wallpaper that
is no longer there. One command now applies the wallpaper and regenerates
immediately, reusing the colour cache.

**35 — `waypaper --restore` was broken by design.** Deploy overwrote
`waypaper/config.ini` with a copy that has no wallpaper key, so restore could
never work after an install. Deploy now preserves the live key the same way it
already preserves `hyprpaper.conf`.

**36 — the #32 dedup broke the standalone daemons.** Moving the `listactive`
parser into `lib/wallpaper.sh` left `wallust-hyprpaper-sync.sh` and
`wallpaper-restore.sh` calling a function nothing had sourced — both run
outside the CLI, so bootstrap never loads the library. The `|| true` swallowed
the "command not found" and every wallpaper resolved to nothing, which looks
exactly like "no wallpaper is set": wallust never re-registered. Both scripts
now source the installed library and carry the same parsing as an inline
fallback, so a missing library still cannot silently disable them.

**37 — the theme `@import` pointed at a path deploy wipes.** The template
imported `themes/active.css`, which resolves under `styles/` — a directory
deploy replaces wholesale, so every `hyprx install` deleted the target and
waybar exited on the missing import. The import is now `../themes/active.css`,
which resolves to the deployed `waybar/themes/` directory that survives
installs.

**38 — the volume icons were never the bug.** `pulseaudio` used Font Awesome
U+F026–F028, which the Nerd Font on this system contains — the "full stop" was
Caudex having no such glyph and no fallback configured. Swapping in U+E040–E042
made it worse: nothing installed covers those, so they fell back to B612 Mono.
Reverted to the original icons; the real fix was the `"JetBrainsMono Nerd
Font"` fallback already added to `styles/base.css`, verified by `fc-match`
charset queries against the installed fonts.

**39 — `hyprx wallpaper set` asked hyprctl to do something hyprpaper rejects.**
Current hyprpaper builds expose only `listactive` over IPC, so `hyprctl
hyprpaper wallpaper` fails every time. The command now sets through `waypaper
--wallpaper` and verifies through `listactive`, since waypaper exits 0 even
when it set nothing.

Found by running install/doctor/clean on the target laptop, same as 21–39.

**42 — doctor missed user-scope units.** The Managed Services section probed
the system scope only, so `pipewire` (a user unit, enabled) was reported
"not installed" while the install stage said "already enabled (user)".
Finding 26 unified the unit *name* but not the scope *probe*: doctor now
resolves through `hyprx_service_scope` and scopes the `is-enabled` call the
same way. Cosmetic only — the line was info, never tallied — but install and
doctor disagreeing about one machine is what 26 was supposed to make
unreintroducible. Suite-asserted with a split-scope `systemctl` stub.

**43 — install left wallust colours stale.** Deploy overwrites the generated
colours with repo defaults, and the sync daemon only reacts to wallpaper
*changes* — same wallpaper, no change, no regeneration. The bar wore defaults
with a live wallpaper and a warm cache, and nothing reported it. Deploy now
re-applies the cached colours for the live wallpaper on success (a copy on a
cache hit, not a render); a failure warns with the one-command recovery
instead of gating the pipeline, which would be finding 24 in reverse.

**44 — drift warned on by-design diffs, and the apps table could never leave
Unknown.** `hyprpaper.conf` carries the live wallpaper path (deploy preserves
it, the sync script rewrites it), `waypaper/config.ini` keeps the live key,
and the seven wallust outputs must never be hand-edited — so the drift
section warned on every healthy machine, training everyone to ignore it.
Those basenames are now excluded from the drift diff; a real local edit
still warns, both suite-asserted. Separately, the Configuration table read
`$TERMINAL` and friends, which nothing HyprX runs ever sets, and README
pointed at `hyprx config set` for apps — a key that does not exist and is
rejected by validation. The table now parses `config/hypr/apps.lua`, the file
the keybinds actually read; README documents the real workflow (edit
`apps.lua`, add the package, add the provider mapping).

**45 — battery "health" was the state of charge.** The battery section divided
`charge_now` by `charge_full` and labelled it "health … of design capacity":
a half-charged healthy battery reported 47% and warned, and the number swung
with the charge level (97% the day before at near-full charge). Health is
`charge_full` over `charge_full_design` — 64% on this machine, genuinely worn
but not what was printed. Suite-asserted with a fixture sysfs tree; the
section takes `HYPRX_SYS_POWER_SUPPLY` so the test never touches `/sys`.

**46 — the summary lied about zero-byte work.** A `--deep` run that cleared
caches and deleted 4 coredumps, all measuring 0 bytes, ended with "Cleanup
completed. Nothing needed removing" - work happened, the message said none
did. A `CLEANED` counter now tracks destructive actions separately from
reclaimed bytes, so the three endings are "Freed X", "cleared N items that
were already empty", and "nothing needed removing". The package-cache step
also never reached the total (its deletions were invisible to the summary);
it is measured before/after like every other step. Related myth-busting on
that same run: the 4.3G pacman cache holds exactly one version per package,
so `paccache -r` correctly frees ~0 by design; the 1.6G Brave cache is
deliberately never touched; the remaining bulk is other apps' caches
(wallust's own 248M, go-build, torbrowser) plus ~207M orphaned by
uninstalling spotify and firefox.

## Still open

- **#20** shared shell helpers: done. The three `command -v … || exec …`
  click-launchers (sound-manager, wifi-manager, system-monitor) now share
  `config/waybar/scripts/lib-launch.sh`, sourced as a sibling so a broken
  install still reports itself instead of silently dying. The duplicate
  `listactive` parsers went earlier with #32.
- `commands/doctor.sh` table-driving: done. The 19 `if doctor_wants`
  blocks are now 19 `hyprx_doctor_section_*` functions behind one
  `HYPRX_DOCTOR_SECTION_TABLE` registry that also derives run order,
  `doctor_usage`, `DOCTOR_SECTIONS` validation and --only/--skip routing, so
  adding a section is one function plus one table line and the lists cannot
  drift. The file went 1235 → ~1280 lines, not ~750: the deeper dedup behind
  that estimate would have merged section bodies and risked behaviour, so it
  was deliberately not done. Verified without the suite by golden-output diff
  (9 scenarios incl. --json/--only/--skip/help/rejections: identical exit
  codes and bytes), ShellCheck clean under the pinned config, and a runtime
  guard that exits 1 naming the section if the table ever points at a missing
  function. The one compromise the table forces: sections dispatch by name,
  which ShellCheck cannot see, so the file carries a scoped SC2329 disable
  (same pattern as clean.sh's EXIT-hook disable).