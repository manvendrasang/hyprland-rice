## License

Copyright © 2026 Manvendra Sang. All rights reserved.

This repository and all of its contents are proprietary software.

No permission is granted to use, copy, modify, reproduce, distribute,
publish, sublicense, sell, or incorporate any portion of this software
into another project without prior written permission from the copyright
holder.

This restriction applies to the current version and all historical
versions, commits, releases, branches, and other versions of the
repository.(all past commits and updates and future ones as well are included)

Viewing or accessing this repository does not grant a license or any
other right to use the software.

For licensing or commercial-use inquiries, contact the copyright holder.


# HyprX

A single, opinionated Hyprland desktop installer for Arch Linux — one flat configuration, automatic package validation, and safe rollback of anything it changes.

There's no profile switching or optional modules — HyprX installs one complete, fixed desktop setup: Hyprland, Waybar, development tools, gaming utilities, media tools, and networking, all in one pass. If you want a different set of packages, edit `packages.list` directly.

## Requirements

- Arch Linux (or an Arch-based distro)
- `bash`
- `pacman`, and optionally `yay` or `paru` for AUR packages
- `git`

## Getting started

```bash
git clone https://github.com/manvendrasang/hyprland-rice.git
cd hyprland-rice
./install.sh
```

This installs HyprX to `~/.local/share/hyprx` and symlinks `hyprx` into `~/.local/bin`. Once installed, `hyprx` is a standalone copy — it no longer depends on which branch you have checked out in your clone, so you can safely switch branches for development without changing what the installed `hyprx` command actually does.

Re-run `./install.sh` any time to update the installed copy to match your current checkout. To remove it:

```bash
./uninstall.sh
```

This only removes the HyprX tool itself — it does not undo any packages or configs HyprX has installed on your system. Run `hyprx rollback` first if you need that.

## Commands

```
hyprx install     Install packages and deploy configs
hyprx update       Update installed packages
hyprx rollback list         Show available snapshots
hyprx rollback latest       Undo the most recent install
hyprx rollback <id>         Undo a specific snapshot
hyprx clean        Clean up temporary/cache files
hyprx doctor       Diagnose system health
hyprx help         Show usage
```

## What gets installed

Everything in `packages.list` (one package per line, edit directly to customize):

- **Desktop**: Hyprland, Waybar, Rofi, Kitty, SwayNC, Thunar
- **Development**: git, neovim, VS Code, lazygit, GitHub CLI
- **Gaming**: Steam, GameMode, MangoHud
- **Media**: mpv, VLC, Spotify (via spotify-launcher), pavucontrol, playerctl
- **Networking**: NetworkManager, Bluetooth (bluez)

Services enabled: `bluetooth`, `docker`, `NetworkManager`, `pipewire` (see `services.list`).

Dotfiles deployed to `~/.config/`: `hypr` and `waybar` (see `config/`).

Some packages need extra system setup before they'll install — for example `steam` requires the `multilib` repository enabled in `/etc/pacman.conf`. When a package fails validation for a known reason like this, HyprX tells you exactly what to do about it instead of just saying "not found."

## Rollback

Every `hyprx install` run saves a snapshot of exactly what it changed:

- Which packages were **newly** installed (packages that were already on your system are never touched or tracked)
- Any config directories it deployed — with an automatic backup of whatever was there before, if anything

```bash
hyprx rollback list      # see what's available
hyprx rollback latest     # undo the most recent install
```

If a config directory existed before the install, rollback restores it from backup. If it didn't exist before (a fresh deployment), rollback removes it. Either way, you're returned to exactly the state you were in before HyprX touched anything.

Config deployment is atomic — new content is fully staged before anything live is touched, so a partially-applied config can't be left behind mid-copy, even for a live-reloading process like Hyprland watching its own config directory.

## Development

```bash
bash tests/run.sh
```

Runs the full test suite: unit tests, ShellCheck, and syntax checks. CI runs the same suite on every push and pull request, split into a `Lint` job and a `Unit Tests` job (the latter runs inside an Arch Linux container, since `pacman`-dependent tests need a real Arch environment).

### Layout

Every directory maps to one job. Within a directory, each file is one
feature or one concern — nothing in here is a grab-bag.

```
packages.list   Flat list of everything HyprX installs (one package per line)
services.list   Flat list of systemd services HyprX enables
install.sh      Installs the hyprx tool itself into ~/.local/share/hyprx (not packages)
uninstall.sh    Removes the installed hyprx tool (packages/configs untouched - see Rollback)
```

**`bin/`** — CLI entry point.
```
hyprx           Resolves its own real path, sources lib/bootstrap.sh, dispatches
                 to commands/<name>.sh based on argv[1] (defaults to "help")
```

**`commands/`** — one file per `hyprx <command>`, matched 1:1 to the
`## Commands` table above.
```
install.sh      hyprx install    -> calls run_install_engine (lib/installer/engine.sh)
update.sh       hyprx update     -> pacman/yay/paru -Syu, package-manager aware
rollback.sh     hyprx rollback   -> list / latest / <id>, backed by lib/installer/snapshot.sh
clean.sh        hyprx clean      -> conservative cache/thumbnail/old-screenshot cleanup only
doctor.sh       hyprx doctor     -> read-only system health report (config, packages, services)
help.sh         hyprx help       -> usage text (also the default with no args)
```

**`lib/`** — shared library code, sourced by every command via
`lib/bootstrap.sh`. Nothing in here is a CLI entry point itself.
```
bootstrap.sh    Sources every other lib/*.sh and exports HYPRX_* path vars
config.sh       Loads config/hyprx.conf into shell vars (load_config)
detect.sh       OS/distro detection (reads /etc/os-release)
packages.sh     Package manager detection (yay > paru > pacman)
logger.sh       Structured logging to ~/.local/state/hyprx/hyprx.log
ui.sh           Terminal colors + section/header/divider helpers
table.sh        table_header/table_row - the two-column tables doctor.sh prints
progress.sh     Text progress bar (used during package installs)
spinner.sh      Background-process spinner (tput civis, braille spinner glyphs)
utils.sh        Generic one-liners (command_exists, is_root, timestamp)

installer/      The actual install engine - everything commands/install.sh calls into
  engine.sh          run_install_engine - orchestrates the full install, in order
  preflight.sh        Pre-flight checks before touching anything
  compatibility.sh    Distro/dependency compatibility gate
  resolver.sh          Reads packages.list -> PACKAGE_QUEUE
  requirements.sh      Loads database/package-requirements.conf (steam/wine/etc hints)
  replacements.sh       Loads database/package-replacements.conf (e.g. code -> code-bin)
  validator.sh          Validates PACKAGE_QUEUE, applies replacements/requirements
  install_packages.sh    Actually installs, tracks INSTALLED/SKIPPED/FAILED
  retry.sh                Generic retry() wrapper with backoff, used around installs
  failure_logger.sh        Appends failed packages to hyprx-install.log
  deploy.sh                Deploys config/{hypr,waybar,wlogout,swaync,swappy,rofi,waypaper}
                             to ~/.config/ - the HYPRX_CONFIG_TARGETS list here is the
                             single source of truth for what counts as a "dotfile"
  snapshot.sh               Snapshot storage (~/.local/state/hyprx/snapshots) - what
                              hyprx rollback reads from
  recovery.sh                Saves/restores install.state for resuming a failed install
  report.sh                   Generates HyprX-Install-Report.txt at end of install
```

**`config/`** — the actual dotfiles that get deployed to `~/.config/`,
one directory per app (see `HYPRX_CONFIG_TARGETS` in `deploy.sh` above
for the authoritative list), plus HyprX's own settings file.
```
hyprx.conf      HyprX's own settings (read by lib/config.sh) - not deployed anywhere
hypr/           Hyprland itself: hyprland.lua (binds/autostart), hypridle, etc.
waybar/         Status bar: config.jsonc, style.css, styles/, scripts/, themes/
rofi/           App launcher/dmenu theme
wlogout/        Logout/power menu
swaync/         Notification daemon config
swappy/         Screenshot annotation tool config
waypaper/       Wallpaper picker config
```

**`database/`** — small flat lookup tables the installer reads at
runtime, never hand-edited by the user during normal use.
```
package-requirements.conf   pkg=hint text - shown when a package needs manual
                             setup first (e.g. steam needs [multilib] enabled)
package-replacements.conf   pkg=replacement - packages.list entries that map to
                             a different real package name (code -> code-bin)
deprecated-packages.conf    Packages HyprX no longer installs but may still see
                             referenced in an old snapshot/report
mirrors.conf                Mirror-related lookups for package operations
```

**`scripts/`** — standalone utility scripts invoked directly (by
keybinds in `hyprland.lua`, by Waybar module `on-click`s, or manually),
as opposed to `lib/` which is only ever sourced. Nothing here is
reached through the `hyprx` CLI.
```
settings-menu.sh        SUPER+I - rofi-based HyprX settings menu
power-profile-cycle.sh  SUPER+F5 - cycles ASUS fan/power profiles (asusctl)
wallpaper-restore.sh    Runs at session start - restores last wallpaper via
                          waypaper --restore, falls back to --random on a fresh install
gpu-offload-setup.sh    Sets up PRIME/dGPU offload env vars for a hardcoded
                          list of GPU-heavy apps
prime-run.sh            On-demand "run this one app on the dGPU" launcher
fix-sddm-greeter.sh     Syncs SDDM's own Hyprland greeter config with the user's
reload-hypr.sh          hyprctl reload - trivial config-reload helper
reload-waybar.sh        Kill + relaunch waybar (used after editing waybar configs)
backup-config.sh        Ad-hoc ~/.config snapshot to a timestamped folder
restore-config.sh       Restores from the HyprX-managed backup at ~/.config/hyprx-backup
dev-sync.sh             Dev-loop helper for syncing local changes while iterating
```

**`tests/`** — the test suite `bash tests/run.sh` runs (unit tests,
ShellCheck, syntax checks - see `## Development` above). One
`test_*.sh` file per subsystem, named after what it covers:
```
run.sh              Entry point - runs everything below plus ShellCheck/syntax
common.sh / setup.sh / teardown.sh   Shared fixtures, test env setup/teardown
test_cli.sh          bin/hyprx dispatch behavior
test_bootstrap.sh    lib/bootstrap.sh sourcing/exports
test_config.sh       lib/config.sh / hyprx.conf loading
test_detection.sh    lib/detect.sh, lib/packages.sh
test_logging.sh      lib/logger.sh
test_progress.sh     lib/progress.sh
test_packages.sh     lib/installer/resolver.sh, validator.sh
test_requirements.sh lib/installer/requirements.sh
test_replacements.sh lib/installer/replacements.sh
test_installer.sh    lib/installer/engine.sh end-to-end
test_install.sh      commands/install.sh
test_deploy.sh        lib/installer/deploy.sh (config deployment)
test_recovery.sh      lib/installer/recovery.sh (resume-after-failure)
test_snapshot.sh      lib/installer/snapshot.sh (rollback data)
test_report.sh        lib/installer/report.sh
test_permissions.sh   File permission expectations across the repo
test_scripts.sh       scripts/*.sh (the standalone utilities, not lib/)
test_shellcheck.sh    Runs ShellCheck across the repo
test_syntax.sh        bash -n syntax check across the repo
test_source.sh        Every lib/*.sh sources cleanly on its own
test_smoke.sh         Fast end-to-end sanity pass
test_coverage.sh       Meta-test: flags files with no corresponding test_*.sh
```

> **Note:** `lib/bootstrap.sh` exports `HYPRX_THEMES="$ROOT_DIR/themes"`,
> but no `themes/` directory currently exists in the repo. Either it's
> planned but not yet built, or it's dead code left over from an earlier
> design — worth resolving next time `lib/bootstrap.sh` is touched.

## Known limitations

- Arch Linux only — package management is built around `pacman`/`yay`/`paru`
- No distro package yet (AUR, etc.) — `install.sh` gives you a standalone install, but there's no `pacman -S hyprx` style package
- One fixed configuration — no profiles or optional modules; edit `packages.list`/`services.list` directly to customize
