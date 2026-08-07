# HyprX

A modular, profile-driven installer for a Hyprland desktop on Arch Linux — built around dependency-aware modules, automatic package validation, and safe rollback of anything it changes.

This isn't just a rice — it's an installer framework. Modules declare their own packages, services, and config directories; profiles pick which modules to install; the engine handles ordering, validation, and deployment; and every install run leaves behind a snapshot you can undo.

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
hyprx install              Install modules for the current profile
hyprx update                Update installed modules
hyprx rollback list         Show available snapshots
hyprx rollback latest       Undo the most recent install
hyprx rollback <id>         Undo a specific snapshot
hyprx clean                 Clean up temporary/cache files
hyprx doctor                Diagnose system and module health
hyprx profile list          List available profiles
hyprx profile current       Show the active profile
hyprx profile show <name>   Show a profile's modules
hyprx profile use <name>    Switch the active profile
hyprx profile create <id>   Create a new profile (interactive, or via flags)
hyprx help                  Show usage
```

## Profiles

A profile is just a named set of modules. Built-in profiles:

| Profile | Description |
|---|---|
| `developer` | Development workstation |
| `gaming` | Gaming workstation |
| `laptop` | Laptop-oriented setup |
| `minimal` | Minimal Hyprland installation |
| `custom` | User-defined, empty by default |

Create your own:

```bash
hyprx profile create work --name "Work Setup" --description "No gaming, no media" --modules "desktop,development"
```

Or run it with no flags for an interactive prompt that lists available modules to pick from.

## Modules

Each module is a directory under `modules/` with a `module.conf` describing its metadata, plus a `packages.list` (one package per line) and optionally a `services.list` and a set of config directories to deploy.

| Module | Optional | Depends on | What it installs |
|---|---|---|---|
| `desktop` | No | — | Hyprland, Waybar, Rofi, Kitty, Dunst — plus deploys `~/.config/hypr` and `~/.config/waybar` |
| `gaming` | Yes | `desktop` | Steam, GameMode, MangoHud |
| `development` | Yes | `desktop` | Developer tooling |
| `media` | Yes | `desktop` | mpv, VLC, Spotify, pavucontrol, playerctl |
| `networking` | Yes | `desktop` | NetworkManager, Bluetooth |
| `ai` | Yes | `desktop` | Currently an empty placeholder — no packages defined yet |

`desktop` is the only module that deploys dotfiles right now. A module opts into config deployment by setting `CONFIG_DIRS="dirname1 dirname2"` in its `module.conf` — no code changes needed to add more later.

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

Runs the full test suite: unit tests, integration tests against every profile, ShellCheck, and syntax checks. CI runs the same suite on every push and pull request, split into a `Lint` job and a `Unit Tests` job (the latter runs inside an Arch Linux container, since `pacman`-dependent tests need a real Arch environment).

### Layout

```
install.sh    Installs the hyprx tool itself (not packages)
uninstall.sh  Removes the installed hyprx tool
bin/          Entry point (hyprx)
commands/     One file per CLI command
lib/          Shared library code
  installer/  Install engine, validation, snapshots, config deploy
  profile/    Profile loading and validation
  module/     Module loading and validation
modules/      Installable modules (packages, services, configs)
profiles/     Profile definitions (which modules to install)
config/       Dotfiles that get deployed by modules
database/     Small lookup tables (package replacements, requirement hints)
tests/        Test suite
```

## Known limitations

- Arch Linux only — package management is built around `pacman`/`yay`/`paru`
- No distro package yet (AUR, etc.) — `install.sh` gives you a standalone install, but there's no `pacman -S hyprx` style package
- The `ai` module is an intentional placeholder with no packages defined
