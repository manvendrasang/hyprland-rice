# HyprX

A single, opinionated Hyprland desktop installer for Arch Linux — one flat configuration, automatic package validation, and safe rollback of anything it changes. There's no profile switching or optional modules — HyprX installs one complete, fixed desktop setup: Hyprland, Waybar, development tools, gaming utilities, media tools, and networking, all in one pass. If you want a different set of packages, edit `packages.list` directly.

## What Changes This Project Brings

- **Packages installed** (~50): Hyprland, Waybar, Rofi, Kitty, SwayNC, Thunar, Hyprlock, Hypridle, development tools (git, neovim, VS Code, lazygit, GitHub CLI), gaming utilities (Steam, GameMode, MangoHud), media tools (mpv, VLC, Spotify, pavucontrol, playerctl), networking (NetworkManager, Bluetooth, firewalld), GPU management (nvidia-utils, supergfxctl, asusctl, rog-control-center), and system utilities (nwg-look, nwg-displays, fastfetch, wallust, cliphist, wl-clipboard, gsimplecal, grim, slurp, swappy, rofimoji, waypaper)
- **Systemd services enabled**: bluetooth, docker, firewalld, NetworkManager, pipewire, supergfxd, asusd
- **Dotfiles deployed to `~/.config/`**: hypr, waybar, wlogout, swaync, swappy, rofi, waypaper, wallust, gtk-3.0
- **Dynamic theming**: wallpaper changes automatically regenerate color schemes across all apps via wallust
- **GPU offload**: PRIME render-offload .desktop overrides for GPU-heavy apps
- **CLI tool**: `hyprx` command for install, update, rollback, clean, and doctor operations

## Installation

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

### Command Details

**`hyprx install`** — Reads `packages.list`, validates each package against official repos and AUR, applies known replacements (e.g., `code` → `visual-studio-code-bin`), installs via the detected package manager (yay > paru > pacman), deploys all configs atomically, sets up GPU offload, and saves a snapshot for rollback.

**`hyprx update`** — Runs a full system update via the detected package manager, refreshes the package database, removes orphaned packages, and cleans the package cache.

**`hyprx rollback list`** — Shows all available snapshots with their package/config counts and timestamps.

**`hyprx rollback latest`** — Undoes the most recent install: removes newly installed packages and restores/removes config directories to their pre-install state.

**`hyprx rollback <id>` — Undoes a specific snapshot by ID.

**`hyprx clean`** — Conservative cleanup: removes stale pacman cache files, prompts to remove orphaned packages, deletes screenshots older than 2 days, clears thumbnail/shader caches, vacuums journal entries older than 7 days, and removes /tmp files older than 1 day (owned by current user). Supports `--dry-run` to preview.

**`hyprx doctor`** — Read-only system health report covering: config validation (JSON/Lua/hyprlock syntax), deployment drift, storage, memory, swap, systemd services, session health, hybrid GPU status, network/radios, pacman state, and a summary. Saves timestamped reports to `~/.local/state/hyprx/reports/`.

## Directory Layout

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

**`commands/`** — one file per `hyprx <command>`, matched 1:1 to the Commands table above.
```
install.sh      hyprx install    -> calls run_install_engine (lib/installer/engine.sh)
update.sh       hyprx update     -> pacman/yay/paru -Syu, package-manager aware
rollback.sh     hyprx rollback   -> list / latest / <id>, backed by lib/installer/snapshot.sh
clean.sh        hyprx clean      -> conservative cache/thumbnail/old-screenshot cleanup only
doctor.sh       hyprx doctor     -> read-only system health report (config, packages, services)
help.sh         hyprx help       -> usage text (also the default with no args)
```

**`lib/`** — shared library code, sourced by every command via `lib/bootstrap.sh`. Nothing in here is a CLI entry point itself.
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
  deploy.sh                Deploys config/{hypr,waybar,wlogout,swaync,swappy,rofi,waypaper,wallust,gtk-3.0}
                           to ~/.config/ - the HYPRX_CONFIG_TARGETS list here is the
                           single source of truth for what counts as a "dotfile"
  snapshot.sh               Snapshot storage (~/.local/state/hyprx/snapshots) - what
                           hyprx rollback reads from
  recovery.sh                Saves/restores install.state for resuming a failed install
  report.sh                   Generates HyprX-Install-Report.txt at end of install
```

**`config/`** — the actual dotfiles that get deployed to `~/.config/`, one directory per app (see `HYPRX_CONFIG_TARGETS` in `deploy.sh` above for the authoritative list), plus HyprX's own settings file.
```
hyprx.conf      HyprX's own settings (read by lib/config.sh) - not deployed anywhere
hypr/           Hyprland itself: hyprland.lua (binds/autostart), hypridle, etc.
waybar/         Status bar: config.jsonc, style.css, styles/, scripts/, themes/
rofi/           App launcher/dmenu theme
wlogout/        Logout/power menu
swaync/         Notification daemon config
swappy/         Screenshot annotation tool config
waypaper/       Wallpaper picker config - its post_command is what
                triggers dynamic theming on every wallpaper change
wallust/        Dynamic theming: wallust.toml + templates/ - see the
                "Dynamic Theming" section above
```

**`database/`** — small flat lookup tables the installer reads at runtime, never hand-edited by the user during normal use.
```
package-requirements.conf   pkg=hint text - shown when a package needs manual
                            setup first (e.g. steam needs [multilib] enabled)
package-replacements.conf   pkg=replacement - packages.list entries that map to
                            a different real package name (code -> code-bin)
deprecated-packages.conf     Packages HyprX no longer installs but may still see
                            referenced in an old snapshot/report
mirrors.conf                Mirror-related lookups for package operations
```

**`scripts/`** — standalone utility scripts invoked directly (by keybinds in `hyprland.lua`, by Waybar module `on-click`s, or manually), as opposed to `lib/` which is only ever sourced. Nothing here is reached through the `hyprx` CLI.
```
settings-menu.sh        SUPER+I - rofi-based HyprX settings menu
power-profile-cycle.sh  SUPER+F5 - cycles ASUS fan/power profiles (asusctl)
wallpaper-restore.sh    Runs at session start - restores last wallpaper via
                        waypaper --restore, falls back to --random on a fresh install
gpu-offload-setup.sh    Sets up PRIME/dGPU offload env vars for GPU-heavy apps
prime-run.sh            On-demand "run this one app on the dGPU" launcher
apply-wallust-theme.sh  Runs wallust + reloads affected apps
fix-sddm-greeter.sh     Syncs SDDM's own Hyprland greeter config with the user's
reload-hypr.sh          hyprctl reload - trivial config-reload helper
reload-waybar.sh        Kill + relaunch waybar (used after editing waybar configs)
backup-config.sh        Ad-hoc ~/.config snapshot to a timestamped folder
restore-config.sh       Restores from the HyprX-managed backup at ~/.config/hyprx-backup
dev-sync.sh             Dev-loop helper for syncing local changes while iterating
```

**`tests/`** — the test suite. Run it with `bash tests/run_tests.sh`; the full transcript of the most recent run is written to `tests/test-results.log`. One self-contained script covers unit tests, ShellCheck, syntax checks, deploy/rollback round-trips, dry-run semantics, and the `clean` sandbox.

## Files Touched by HyprX Upon Installation

| Path | Action |
|---|---|
| `~/.local/share/hyprx/` | Created — installed copy of the tool |
| `~/.local/bin/hyprx` | Symlink created |
| `~/.local/bin/prime-run` | Symlink created |
| `~/.local/bin/hyprx-settings` | Symlink created |
| `~/.config/hypr/` | Deployed (backed up if exists) |
| `~/.config/waybar/` | Deployed (backed up if exists) |
| `~/.config/wlogout/` | Deployed (backed up if exists) |
| `~/.config/swaync/` | Deployed (backed up if exists) |
| `~/.config/swappy/` | Deployed (backed up if exists) |
| `~/.config/rofi/` | Deployed (backed up if exists) |
| `~/.config/waypaper/` | Deployed (backed up if exists) |
| `~/.config/wallust/` | Deployed (backed up if exists) |
| `~/.config/gtk-3.0/` | Deployed (backed up if exists) |
| `~/.local/share/applications/*.desktop` | GPU offload overrides created |
| `~/.local/state/hyprx/` | Created — logs, snapshots, reports |
| `~/.local/state/hyprx/snapshots/` | Created — rollback data |
| `~/.local/state/hyprx/reports/` | Created — doctor reports |
| `~/.local/state/hyprx/hyprx.log` | Created — operation log |
| `~/.local/state/hyprx/hyprx-install.log` | Created — failure log |
| `~/.local/state/hyprx/install.state` | Created during install, removed on completion |
| `~/.local/state/hyprx/deployed-targets` | Created — tracks deployed config dirs |
| `~/.local/state/hyprx/config-backups/` | Created — config backups for rollback |
| System packages | Installed via pacman/yay/paru |
| Systemd services | Enabled per `services.list` |

## Known Limitations

- Arch Linux only — package management is built around `pacman`/`yay`/`paru`
- No distro package yet (AUR, etc.) — `install.sh` gives you a standalone install, but there's no `pacman -S hyprx` style package
- One fixed configuration — no profiles or optional modules; edit `packages.list`/`services.list` directly to customize
