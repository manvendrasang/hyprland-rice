# HyprX

A single opinionated Hyprland desktop installer for Arch Linux.
It installs one fixed desktop setup — no profiles, no optional modules.
Edit `packages.list` and `services.list` to change what you get.

**Licence:** proprietary. All rights reserved. See `LICENSE.md`.

## Install

```
git clone https://github.com/manvendrasang/hyprland-rice.git
cd hyprland-rice
./install.sh
```

Copies the tool to `~/.local/share/hyprx` and symlinks `hyprx`, `prime-run` and
`hyprx-settings` into `~/.local/bin`. The installed copy is standalone, so it
does not change when you switch branches in your clone — re-run `./install.sh`
to resync it. `./uninstall.sh` removes the tool but undoes nothing else; run
`hyprx rollback` first if you want that.

## Before you install

Arch Linux with `sudo` working, a Wayland/Hyprland session, and an AUR helper
(`yay` or `paru`) — the gate checks all of this and fails fast if anything is
missing. About five packages are AUR-only; without a helper they cannot
install.

Put your own images in `~/Pictures/Wallpapers` first. No wallpapers ship with
this repo and nothing creates that folder: with no images the restore script
finds nothing, wallust never runs, and the bar wears its default colours until
you add some.

After installing, set your preferred apps — terminal, browser, editor, file
manager and launcher all start as `Unknown` (`hyprx config set ...`). The theme
starts at `default`; `hyprx config set THEME one-dark` is opt-in.

## What install does

Eight stages, in order: **gate** (check the machine) → **resolve** the package
queue from `packages.list`, or resume an interrupted install → **validate**
every name against the repos, applying known replacements → **install** with
retries and a summary → **deploy** configs to `~/.config` → **fonts** →
**services** → **snapshot and report**.

A failure in the install, font or service stage does not abort the run: the
configs, snapshot and report are what you need to recover, so it finishes and
exits non-zero with the failures listed.

## Commands

```
hyprx install [--dry-run]   set up the desktop
hyprx update                update the packages HyprX manages
hyprx rollback list         show snapshots
hyprx rollback latest       undo the most recent install
hyprx rollback <id>         undo one snapshot (id looks like 20261004-004630)
hyprx clean [--deep] [--dry-run] [--yes]   reclaim disk space
hyprx config list|get|set|unset|path       read and change settings
hyprx doctor [--only ...] [--skip ...] [--json] [--deep] [--restart]
hyprx wallpaper set|next|current         set or rotate the wallpaper
hyprx help
```

`--dry-run` on install, clean and rollback reports what would change and changes
nothing. Both rollback actions also ask for confirmation before touching
anything.

**rollback** removes only packages HyprX installed; anything you already had is
left alone. `list` shows every snapshot with its package and config counts,
`latest` undoes the most recent install, and `<id>` undoes one specific snapshot.
Snapshot IDs carry nanoseconds, so two rollbacks in the same second cannot
collide and silently overwrite each other.

**clean** clears the pacman cache, orphaned packages, screenshots older than
`SCREENSHOT_AGE_DAYS` (2), thumbnail/shader/fontconfig caches, journal entries
older than `JOURNAL_RETENTION_DAYS` (7), your own `/tmp` files older than
`TMP_AGE_DAYS` (1), and prunes snapshots (`SNAPSHOT_KEEP`, 5), doctor reports
(`REPORT_KEEP`, 10) and log generations (`LOG_KEEP`, 3). Every step reports the
bytes it actually reclaimed, and a run that freed nothing says so. `--deep` adds
the AUR build cache, NVIDIA shaders, pip, the trash and coredumps — never a
browser profile. `HYPRX_CLEAN_ROOT` redirects every home-relative target, which
is how the test suite exercises real deletions.

**config** keys, all validated on write:

| Key | Meaning |
|---|---|
| `THEME` | which waybar theme to use (`one-dark`, or `default`) |
| `PACKAGE_MANAGER` | `yay`, `paru` or `pacman` |
| `LOG_LEVEL` | how much detail the log keeps |
| `AUTO_CONFIRM` | skip yes/no questions |
| `BACKUP_ON_DEPLOY` | keep a copy before overwriting configs |
| `ENABLE_GPU_OFFLOAD` | PRIME render offload for heavy apps |

**doctor** runs 19 checks: `configuration`, `applications`, `system`,
`validation`, `drift`, `storage`, `memory`, `swap`, `systemd`, `services`,
`session`, `gpu`, `network`, `pacman`, `daemons`, `battery`, `diskusage`,
`fonts`, `manifest`. Exit `0` clean, `1` problems found, `2` bad usage. Run it
after changing a template or a list — it is the only thing that tells you a
template stopped covering its consumer.

## Automation (GUI foundation)

Three mechanisms for scripted and graphical frontends. Human output is
untouched by all of them.

- **Events:** `hyprx <cmd> --events` emits `HYPRX_EVENT {...}` JSON lines on
  stderr (v1 schema: `v`, `ts`, `mode`, `type`). `mode` is `live` or
  `dry-run`; every run ends with `run.completed{rc}`, and every failed item
  emits its own `*.failed` first. stdout contracts (`doctor --json`,
  `wallpaper current`) stay pure.
- **Read-only JSON:** `config list|get --json`, `rollback list --json`,
  `wallpaper current --json` (null when unset). `doctor --json` already
  existed and is the pattern the others copy.
- **Single writer:** install, rollback and clean share one lock
  (`$STATE/hyprx.lock`, PID-tracked, stale locks broken). A held lock
  refuses with exit 3. `--password-stdin` feeds sudo one line on stdin for
  TTY-less frontends (validated once via `sudo -S -v`, ticket kept warm;
  the password never touches argv, env, files or logs). Non-interactive
  callers must pre-confirm: preview with `--dry-run`, confirm in the UI,
  then run with `AUTO_CONFIRM=true`.

## Deployed configs

`HYPRX_CONFIG_TARGETS` in `lib/installer/deploy.sh` is the authoritative list;
anything not in it is never deployed.

| Directory | Controls |
|---|---|
| `hypr` | Hyprland: keybinds, wallpaper, idle, lock (split modules, below) |
| `waybar` | the bar, its styles and helper scripts |
| `wlogout` | logout/reboot screen |
| `swaync` | notification popups |
| `swappy` | screenshot annotation |
| `rofi` | launcher and dmenu |
| `waypaper` | wallpaper picker |
| `wallust` | pulls colours from the wallpaper |
| `gtk-3.0` | makes ordinary GTK apps match |

**Seven files are generated by wallust** — `waybar/styles/colors.css`,
`rofi/colors.rasi`, `swaync/colors.css`, `wlogout/colors.css`,
`hypr/colors.lua`, `hypr/colors.conf`, `gtk-3.0/gtk.css`. Never hand-edit them;
any change is lost on the next wallpaper change. Edit the matching template in
`config/wallust/templates/` instead. Colours are cached per wallpaper, so
switching back to a wallpaper you have already used does not regenerate them.

Two files are special. `hyprpaper.conf` ships with no wallpaper block on
purpose — a committed machine-specific path meant hyprpaper started with nothing
— and `scripts/sync-hyprpaper-conf.sh` rewrites it on every wallpaper change.
`waypaper/config.ini` is overwritten by install with a copy that has no wallpaper
key, which used to break `waypaper --restore` after every install; deploy now
preserves the live wallpaper key the same way it preserves `hyprpaper.conf`.

`hypr/hyprland.lua` is an entry point only — it just requires the modules
below in order, so change the module, not the entry. `apps.lua` returns the
shared app table (`terminal`, `fileManager`, `launcher`, `browser`, `runner`)
that `keybinds.lua` reads; everything else only calls the compositor.

| File | Change here to |
|---|---|
| `monitors.lua` | monitor layout, scale, position |
| `apps.lua` | default terminal, file manager, launcher, browser |
| `autostart.lua` | what launches at login |
| `env.lua` | environment variables, NVIDIA/MUX options |
| `general.lua` | cursor behaviour, permission examples |
| `theme.lua` | gaps, borders, rounding, blur, opacity |
| `animations.lua` | curves and animation speeds |
| `layouts.lua` | dwindle/master/scrolling, input, touchpad, gestures |
| `keybinds.lua` | shortcuts and multimedia keys |
| `rules.lua` | window rules and float sizes |

## Files it writes

Created: `~/.local/share/hyprx/` (the tool), `~/.local/bin/` (symlinks),
`~/.local/share/applications/` (GPU offload overrides), and under the state dir
`~/.local/state/hyprx/`: `hyprx.log` (rotated), `hyprx-install.log`,
`HyprX-Install-Report.txt`, `reports/`, `snapshots/`, `config-backups/`,
`deployed-targets`, `last-wallpaper`, and `install.state` while an install runs.

`lib/state.sh` is the single source of truth for those paths and honours
`XDG_STATE_HOME`; overriding `HYPRX_STATE_DIR` relocates all of them.
Regenerable caches live in `~/.cache/hyprx/` because they are not state.

Also changed: system packages via pacman/yay/paru, and the systemd services in
`services.list`.

## Fonts

Caudex only, all four static faces, into `~/.local/share/fonts/hyprx/`. Fetched
from upstream Google Fonts and pinned by SHA256 rather than installed as a
package, because the only Arch option (`ttf-google-fonts-git`) pulls in 22 font
packages and the whole Google catalogue — hundreds of megabytes for one serif
face. Install verifies every file against its pin and installs nothing on a
mismatch; `hyprx doctor --only fonts` re-checks and confirms `fc-match` resolves
them. If Google re-cuts the fonts and a pin fails, re-pin deliberately in
`lib/installer/fonts.sh` after confirming the file is genuinely Caudex.

## Known gaps

None outstanding. `THEME` applies the selected theme through
`waybar/themes/active.css`, which the wallust template imports — it has to live
there rather than in the committed default, because wallust regenerates that
file on every wallpaper change and would destroy an import written into the
default at exactly the moment the theme needs to still be applied.

## Limitations

Arch only; package handling assumes pacman/yay/paru. One fixed configuration.
The GPU, power-profile and hybrid-display packages (`nvidia-utils`,
`supergfxctl`, `intel-gpu-tools`, `asusctl`, `rog-control-center`) install
unconditionally — on other hardware they are inert but present, so drop them from
`packages.list` and `services.list` if they do not apply. This rice targets an
ASUS hybrid-GPU laptop; `scripts/fix-sddm-greeter.sh` is SDDM-specific and
HyprX installs no display manager. One keybind opens a browser that is not
installed by default — change `browser` in `config/hypr/apps.lua` and add the
package. To contribute, read `CONTRIBUTING.md`.