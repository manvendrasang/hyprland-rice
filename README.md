# HyprX

A single opinionated Hyprland desktop installer for Arch Linux.
It installs one fixed desktop setup. There are no profiles and no optional modules.
Edit `packages.list` if you want a different set of packages.

**Licence:** proprietary. All rights reserved. See `LICENSE.md`. This is not a
granting of permission to use, copy or redistribute it.

**If you want to contribute,** `CONTRIBUTING.md` is the short version of the two
rules this codebase actually runs on.

## What it does

Installs roughly 50 packages.
Validates each one against the official repos and the AUR first.
Applies known replacements such as `code` to `visual-studio-code-bin`.
Deploys dotfiles to nine directories under `~/.config/`.
Regenerates every colour scheme from your wallpaper on each change.
Sets up PRIME render offload for GPU heavy apps.
Enables the systemd services listed in `services.list`.
Saves a snapshot so any install can be rolled back.
Ships a CLI called `hyprx`.

## Install

```
git clone https://github.com/manvendrasang/hyprland-rice.git
cd hyprland-rice
./install.sh
```

This installs the tool to `~/.local/share/hyprx` and symlinks it into `~/.local/bin`.
The installed copy is standalone so it does not change when you switch branches in your clone.
Re-run `./install.sh` at any time to resync the installed copy with your checkout.

To remove the tool:

```
./uninstall.sh
```

This does not undo packages or configs. Run `hyprx rollback` first if you need that.

## Commands

```
hyprx install             install packages and deploy configs
hyprx update              update installed packages
hyprx rollback list       show available snapshots
hyprx rollback latest     undo the most recent install
hyprx rollback <id>       undo a specific snapshot
hyprx clean               clean up cache and temporary files
hyprx config              read and change settings
hyprx doctor              diagnose system health
hyprx help                show usage
```

### hyprx install

Reads `packages.list`.
Validates every package against the official repos and the AUR.
Applies known replacements.
Installs through yay then paru then pacman.
Deploys all configs.
Sets up GPU offload.
Saves a rollback snapshot.

`--dry-run` runs every stage and reports what would change without installing anything.

### hyprx update

Runs a full system update.
Removes orphaned packages.
Cleans the package cache.

### hyprx rollback

`list` shows every snapshot with its package count and config count.
`latest` undoes the most recent install.
`<id>` undoes one specific snapshot.

Only packages that HyprX installed are removed. Anything you already had is left alone.

### hyprx clean

Removes stale pacman cache files.
Prompts before removing orphaned packages.
Deletes screenshots older than 2 days.
Clears thumbnail and shader caches.
Vacuums journal entries older than 7 days.
Removes your own `/tmp` files older than 1 day.
Prunes old snapshots. Prunes config backups with no matching snapshot.
Prunes old doctor reports. Prunes rotated log generations.

Every step reports the bytes it actually reclaimed.
A run that freed nothing says so rather than claiming success.
The run total only counts measured savings.
The pacman cache is printed as an upper bound because a cache clean does not
free all of it.

```
hyprx clean                 conservative cleanup
hyprx clean --deep          also clear the large caches. the trash. and coredumps
hyprx clean --dry-run       report every step. remove nothing
hyprx clean --yes           do not prompt before removing orphaned packages
```

`--deep` covers the AUR build cache. NVIDIA shader cache. Fontconfig. Pip.
The trash via `gio trash --empty`. And coredumps.

A browser profile is never touched even under `--deep`.
It regenerates but costs a long re-download and a cold start.

Steps needing sudo are skipped with a message when no cached sudo ticket exists.
The run still completes and still reports what it did free.

Retention is adjustable through the environment.

`SCREENSHOT_AGE_DAYS`
Screenshot age. Default 2.

`TMP_AGE_DAYS`
Your own `/tmp` file age. Default 1.

`JOURNAL_RETENTION_DAYS`
Journal entries kept. Default 7.

`SNAPSHOT_KEEP`
Rollback snapshots kept. Default 5.

`REPORT_KEEP`
Doctor reports kept. Default 10.

`LOG_KEEP`
Rotated log generations kept. Default 3.

`HYPRX_CLEAN_ROOT`
Redirects every home-relative target at another directory.
Home-relative steps then run for real.
System-wide steps are reported instead because they cannot be redirected.
This is how the test suite exercises real deletions.

### hyprx config

Reads and changes `config/hyprx.conf`.

```
hyprx config list           show every setting
hyprx config get <KEY>      print one value
hyprx config set <KEY> <V>  change a value
hyprx config unset <KEY>    restore a default
hyprx config path           print the file location
```

Values are validated before they are written so a typo is rejected immediately.

`THEME`
Waybar theme name. Must exist in `config/waybar/themes/`. Currently not applied. See Known Gaps.

`AUTO_CONFIRM`
`true` or `false`. Answers yes to confirmations such as orphan removal.

`BACKUP_ON_DEPLOY`
`true` or `false`. Backs up existing configs before replacing them.

`ENABLE_GPU_OFFLOAD`
`true` or `false`. Runs GPU offload setup during install.

`LOG_LEVEL`
One of `off` `error` `warn` `info` `debug`. Affects the log file only. Terminal output is unchanged.

`LOG_FILE`
Path to the install failure log. Defaults to the state directory.

`PACKAGE_MANAGER`
One of `auto` `pacman` `yay` `paru`. Pins a manager instead of auto detecting.

### hyprx doctor

Read only health report.
Validates JSON and Lua and hyprlock syntax.
Checks config drift against the repo.
Reports storage. Reports memory. Reports swap.
Reports failed systemd units.
Reports session health and hybrid GPU state.
Reports network. Reports radios. Reports pacman state.
Checks every autostarted daemon rather than only waybar and hyprpaper.
Reports battery level. Reports battery health against design capacity.
Reports temperatures when `lm_sensors` is installed.
Reports where disk space actually goes instead of only filesystem totals.
Suggests a next step for anything actionable.
Saves a timestamped report to `~/.local/state/hyprx/reports/`.

Exits `0` when clean. Exits `1` for warnings only. Exits `2` when errors were found.

```
hyprx doctor                 run everything and save a report
hyprx doctor --only a,b      run only these sections
hyprx doctor --skip c,d      run everything except these
hyprx doctor --no-report     do not write a timestamped report
hyprx doctor --json          machine-readable output instead of the report
```

Sections:

```
configuration  applications  system      validation  drift       storage
memory         swap          systemd     services    session     gpu
network        pacman        daemons     battery     diskusage
fonts          manifest
```

An unknown section name is rejected and the valid names are printed.
Silently running nothing would be indistinguishable from a clean bill of
health.

`gpu` covers hybrid GPU state.
It is a section of its own rather than part of `session`, so `--skip gpu`
turns it off.

`fonts` verifies Caudex against its pinned SHA256 list and confirms `fc-match`
actually resolves it.
An installed-but-unusable font is otherwise invisible: the bar simply renders in
a fallback.

`manifest` cross-checks `database/binary-providers.conf` against `packages.list`
and against the commands `config/` and `scripts/` actually reference.
This is the section that catches a missing runtime dependency before it becomes
a silently broken script.

`--json` emits one object.
It carries `host`. `distro`. `kernel`. `session`. `uptime_seconds`.
It carries `summary`. `suggestions`. and a `findings` array.
Each finding has a `status` of `ok`. `warn`. or `error`.
`--json` is rejected together with `--only` because a partial document would
look complete.

`swaync.service` is expected to sit in `failed`.
HyprX installs it but launches it from the compositor's exec-once chain instead
of enabling it.
Doctor reports it and does not count it.
Any other failed unit is still a warning.

## State directory

Everything HyprX writes lives under one directory.

```
~/.local/state/hyprx/
```

`XDG_STATE_HOME` is honoured when it is set.

```
hyprx.log                  the operation log
hyprx.log.1                the previous generation
hyprx-install.log          per package install failures
HyprX-Install-Report.txt   the most recent install report
reports/                   timestamped doctor reports
snapshots/                 rollback data
config-backups/            pre deploy config copies keyed by snapshot id
deployed-targets           which config directories were last deployed
install.state              interrupted install queue
last-wallpaper             the wallpaper wallpaper-restore.sh last applied
```

`lib/state.sh` is the single source of truth for those paths.
Every consumer reads from it so one `HYPRX_STATE_DIR` assignment relocates all
of them.
Override it to run the tool against a scratch directory.

Regenerable caches stay under `~/.cache/hyprx` where the XDG spec puts them.
They are not state.

`hyprx.log` rotates at 2 MiB and keeps one previous generation.
Neither the log nor the install log had any rotation before.

## Layout

```
packages.list    every package HyprX installs
services.list    every systemd service HyprX enables
install.sh       installs the tool itself
uninstall.sh     removes the tool itself
```

`bin/hyprx`
Resolves its own real path. Sources `lib/bootstrap.sh`. Dispatches to `commands/<name>.sh`.

`commands/`
One file per command.

```
config.sh      hyprx config
clean.sh       hyprx clean
doctor.sh      hyprx doctor
help.sh        hyprx help
install.sh     hyprx install
rollback.sh    hyprx rollback
update.sh      hyprx update
```

`lib/`
Shared code. Sourced by every command. Never a CLI entry point.

```
bootstrap.sh    sources every lib file and exports the HYPRX_ path variables
state.sh        every path HyprX writes to resolved from HYPRX_STATE_DIR
config.sh       loads and validates config/hyprx.conf
detect.sh       probes the OS plus hardware and installed tools
logger.sh       writes to the log honouring LOG_LEVEL. rotates it
packages.sh     package queries. install. remove. update
table.sh        the two column tables doctor prints
ui.sh           terminal colours and section headers
utils.sh        dry run and confirmation and validation helpers
```

`lib/installer/`
The install engine.

```
deploy.sh           copies config directories to ~/.config
engine.sh           runs the install stages in order
failure_logger.sh   records failed packages
fonts.sh            fetches and verifies Caudex
gate.sh             every check run before anything is changed
install_packages.sh the install loop and its summary
recovery.sh         saves state so a failed install can resume
replacements.sh     loads database/package-replacements.conf
report.sh           writes the install report
requirements.sh     loads database/package-requirements.conf
resolver.sh         reads packages.list into the install queue
retry.sh            retry wrapper with backoff
services.sh         enables the services in services.list
snapshot.sh         snapshot storage and rollback
validator.sh        validates the queue and applies replacements
```

`config/`
The dotfiles that get deployed. One directory per app.

`config/hyprx.conf`
HyprX settings. Read by the tool. Never deployed.

`database/`
Lookup tables read by the installer.

```
binary-providers.conf      binary name to the package that provides it
deprecated-packages.conf   packages no longer installed
mirrors.conf               mirror lookups
package-replacements.conf  package name to package name
package-requirements.conf  package to a setup hint
```

`binary-providers.conf` is the guard against the bug class that cost this rice
the most: a binary referenced by the config that nothing installs. It shipped
seven at once — `hyprpaper` (the entire wallpaper and dynamic-theming chain),
`notify-send` (the error handler for six scripts), `hostname`, `fc-cache`,
`fc-match` — and every one failed silently. `hyprx doctor --only manifest`
checks that every declared provider is in `packages.list` and that every command
referenced by `config/` and `scripts/` is either declared or installed.

`scripts/`
Standalone utilities. Run directly by a keybind or by hand. Not reachable from the CLI.

```
apply-wallust-theme.sh   runs wallust then reloads affected apps
backup-config.sh        ad hoc snapshot of the deployed configs
fix-sddm-greeter.sh     syncs the SDDM greeter config
gpu-offload-setup.sh    sets up PRIME offload env vars
power-profile-cycle.sh  cycles ASUS power profiles
prime-run.sh            runs one app on the dGPU
reload-hypr.sh          hyprctl reload
reload-waybar.sh        restarts waybar so it rereads its config
restore-config.sh       restores the HyprX managed backup
settings-menu.sh        rofi settings menu
sync-hyprpaper-conf.sh  points hyprpaper.conf at the live wallpaper
wallpaper-restore.sh    sets the wallpaper at login
```

`tests/`
Run with `bash tests/run_tests.sh`.
The transcript of the last run is written to `tests/test-results.log`.

`tests/review-checks.sh`
The checkable claims from REVIEW.md as an executable script. `--fix` applies the
safe mechanical ones. It reports the reason for each finding in prose, so unlike
the suite it is self-explanatory when something breaks.

## Config files

Nine directories are deployed to `~/.config/`.
That list lives in `HYPRX_CONFIG_TARGETS` in `lib/installer/deploy.sh`.
A directory that is not in that list is never deployed.

`config/hypr/` 6 files. Session config plus lock screen plus idle daemon plus hyprpaper.
`config/waybar/` 23 files. Status bar config, styles, one theme and 13 helper scripts.
`config/wlogout/` 3 files. Logout menu.
`config/swaync/` 3 files. Notification daemon.
`config/swappy/` 1 file. Screenshot annotation tool.
`config/rofi/` 3 files. Launcher and dmenu.
`config/waypaper/` 1 file. Wallpaper picker.
`config/wallust/` 8 files. Theming config plus 7 templates.
`config/gtk-3.0/` 1 file. GTK theme.

### Generated files

These seven are written by wallust. Do not hand edit them.
Any local change is lost on the next wallpaper change.
Edit the matching template in `config/wallust/templates/` instead.

`~/.config/waybar/styles/colors.css` from `waybar-colors.css`. Used by Waybar.
`~/.config/rofi/colors.rasi` from `rofi-colors.rasi`. Used by Rofi and dmenu.
`~/.config/swaync/colors.css` from `swaync-colors.css`. Used by SwayNC.
`~/.config/wlogout/colors.css` from `wlogout-colors.css`. Used by wlogout.
`~/.config/hypr/colors.lua` from `hypr-colors.lua`. Used for Hyprland borders.
`~/.config/hypr/colors.conf` from `hypr-colors.conf`. Used by hyprlock.
`~/.config/gtk-3.0/gtk.css` from `gtk-colors.css`. Used by GTK apps.

The committed copies hold neutral defaults so a fresh clone looks right before wallust runs.

### Special cases

`~/.config/hypr/hyprpaper.conf`
The repo copy has no wallpaper block on purpose.
An earlier one pinned a machine specific path that did not exist so hyprpaper started with nothing.
Because it was committed every install re deployed the same broken path.
`scripts/sync-hyprpaper-conf.sh` now rewrites the path on every wallpaper change.
`hyprx install` preserves a live copy that already has a wallpaper block.

`~/.config/waypaper/config.ini`
waypaper records the last wallpaper it applied in this same file.
`hyprx install` overwrites it with the repo copy which has no wallpaper key.
So `waypaper --restore` cannot work after an install.
`scripts/wallpaper-restore.sh` keeps its own state file and falls back to a random wallpaper.

## Files touched on install

Created under `~/.local/share/hyprx/`
The installed copy of the tool.

Symlinked into `~/.local/bin/`
`hyprx`
`prime-run`
`hyprx-settings`

Deployed to `~/.config/`
The nine directories listed under Config files above.

Created under `~/.local/share/applications/`
GPU offload `.desktop` overrides.

Created under `~/.local/state/hyprx/`
`hyprx.log` operation log.
`hyprx-install.log` failure log.
`snapshots/` rollback data.
`reports/` doctor reports.
`config-backups/` config backups for rollback.
`deployed-targets` tracks which config dirs were deployed.
`install.state` written during install and removed on completion.

Also changed
System packages installed through pacman or yay or paru.
Systemd services enabled per `services.list`.

## Fonts

Caudex is the only font, in all four static faces (Regular, Bold, Italic,
Bold Italic), installed to `~/.local/share/fonts/hyprx/`.

It is fetched directly from the upstream Google Fonts repository and pinned by
SHA256 rather than installed as a package, because the only Arch option —
`ttf-google-fonts-git` — depends on 22 further font packages (`noto-*`,
`adobe-source-*`, `roboto`, `ubuntu`, `fira`, `lato` and more) and installs the
entire Google catalogue. That is hundreds of megabytes for one serif face.
Caudex is 4 files, under 2 MB.

`hyprx install` verifies every file against its pin and refuses to install
anything on a mismatch. `hyprx doctor --only fonts` re-checks the installed
files and confirms `fc-match` resolves them.

If a checksum ever fails because Google re-cut the fonts, re-pin deliberately in
`lib/installer/fonts.sh` after confirming the new file is genuinely Caudex.

## Known gaps

`THEME` does nothing.
`config/waybar/themes/` ships one theme.
`hyprx config set THEME` validates the name but nothing applies it.
Waybar always starts with its default config.
Wiring it up would change your bar so it was left alone.

`waypaper --restore` does not survive an install.
See the special cases above.

## Known limitations

Arch Linux only. Package handling is built around pacman or yay or paru.
No distro package. `install.sh` gives you a standalone install only.
One fixed configuration. No profiles. Edit `packages.list` and `services.list` directly.

### Hardware assumptions

This is a single-GPU-in-everything-except-the-GPU rice for an ASUS hybrid-GPU
laptop, and it says so:

- The GPU, power-profile and hybrid-display packages (`nvidia-utils`,
  `supergfxctl`, `intel-gpu-tools`, `asusctl`, `rog-control-center`) install
  unconditionally. On other hardware they are inert but present. Remove that
  section from `packages.list` and the matching entries from `services.list` if
  they do not apply to you.
- `scripts/fix-sddm-greeter.sh` is for SDDM specifically. HyprX does not install
  a display manager; you need one already configured to reach this login screen.
- One keybind opens a browser that is not installed by default. Edit `browser`
  in `config/hypr/hyprland.lua` and add the package to `packages.list`.
- `doctor` exits 2 on real errors, 1 on warnings, 0 when clean. Run it after any
  change to a template or package list — it is the only thing that will tell you
  a template stopped covering its consumer.
