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

```
packages.list  Flat list of everything HyprX installs
services.list  Flat list of systemd services HyprX enables
install.sh     Installs the hyprx tool itself (not packages)
uninstall.sh   Removes the installed hyprx tool
bin/           Entry point (hyprx)
commands/      One file per CLI command
lib/           Shared library code
  installer/   Install engine, validation, snapshots, config deploy
config/        Dotfiles that get deployed (hypr, waybar) plus hyprx.conf
database/      Small lookup tables (package replacements, requirement hints)
tests/         Test suite
```

## Known limitations

- Arch Linux only — package management is built around `pacman`/`yay`/`paru`
- No distro package yet (AUR, etc.) — `install.sh` gives you a standalone install, but there's no `pacman -S hyprx` style package
- One fixed configuration — no profiles or optional modules; edit `packages.list`/`services.list` directly to customize
