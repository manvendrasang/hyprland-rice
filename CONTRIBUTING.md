# Contributing to HyprX

HyprX is a Hyprland desktop installer for Arch Linux. The dotfiles are the easy
part; the installer is a real piece of software and is held to the standard of
one.

## Before you start

```
bash tests/run_tests.sh        # the gate. 426 assertions.
bash tests/review-checks.sh    # self-explanatory invariant checks
shellcheck -x $(find . -path ./.git -prune -o -name '*.sh' -print) bin/hyprx
```

All three must be clean. CI runs the first and third; `review-checks.sh` is for
you.

## The rule that matters most

**Never report a success you did not measure.**

This is the single defect class that has cost this project the most, in three
separate forms:

- `hyprx clean` added the full pre-trash size to its "bytes reclaimed" total
  without checking whether `gio trash --empty` had succeeded.
- `hyprx install` printed "Installation completed successfully" directly after
  listing twelve failed packages.
- `hyprx doctor --only applications` printed nine red crosses and then "All
  checks passed", exiting 0, because that section bypassed the tallies.

In each case the code was confident and wrong, and the user's only source of
truth was the output. If you cannot measure it, say you did not. If you did not
run it, say you did not run it.

The second rule follows from the first:

**Do not enable `errexit` in a sourced file.**

`bin/hyprx` deliberately runs without `set -e` so that a command can probe
things that legitimately fail and report them. A single `set -e` inside a
sourced library leaks to the caller and turns every later probe into an abort.
This cost a full install once: a `set +e` / `set -e` pair around the package
loop left errexit on, so the first retry of a failing package killed the
process — no retry ladder, no summary, no config deploy, no snapshot, and a
stale `install.state` that made the *next* install resume from a phantom
interruption.

Use `if cmd; then …; else rc=$?; fi` to capture a status without tripping it.

## Declaring a dependency

If you reference a binary from `config/` or `scripts/`, declare it.

```
# database/binary-providers.conf
mycommand         | my-package         | what uses it
```

Then check it with `hyprx doctor --only manifest`, which fails when a declared
provider is not in `packages.list`, or when the config references a command that
is neither declared nor installed.

Seven of these shipped broken at once and every one failed silently — a script
`exec`ing a name that resolves to nothing exits quietly, and fontconfig falls
back without comment. The manifest exists so you never have to notice.

`database/binary-providers.conf` is only for pairs where the binary name and
the package name differ, or where the need is non-obvious. `waybar` in
`packages.list` obviously provides `waybar`.

## Changing a template

If you touch a wallust template, you almost certainly have to touch its consumer
or its committed default.

`wallust` overwrites `config/waybar/styles/colors.css` on the **first wallpaper
change**. So every `@define-color` a template emits must also exist in the
committed default, and every `@var` the consumer stylesheets reference must be
defined by the template. GTK drops a declaration whose custom property is
undefined — along with the whole rule using it — and does so *after* the first
wallpaper change, which is why this bug shipped: a fresh clone looked perfect.

CI asserts both directions. If you add a variable, add it in both places or the
build fails.

## Changing packages.list

`packages.list` is the single source of truth for what gets installed.
`services.list` names services to enable, and `lib/installer/services.sh`
resolves each to a system or user scope by probing systemd — the names give no
hint which is which (`pipewire` is a user unit; `NetworkManager` is a system
unit).

A service whose package is not installed is reported as "no unit file" rather
than failing the install, so `services.list` can be a wish list. But if you add
a service, add its package.

## Tests

`tests/run_tests.sh` is the gate and must stay green.

Write behavioural assertions, not textual ones. The suite used to contain many
checks of the form "does this file contain the string `ensure-waybar.sh`". Those
guard against deleting a fix; they do not guard against breaking behaviour, and
a fatal install-loop bug shipped with 330 of them green.

If you fix a bug, add a test that fails without the fix. The ones that matter:

- Drive the real CLI. The suite runs `hyprx install` end to end with a stubbed
  `pacman` and `sudo` on `PATH`, which is what lets it observe the install
  stage's exit code.
- Assert the exit code and the output together. "Did not abort" and "did not lie
  about success" are different assertions.
- Never call `pass`/`fail` inside a pipeline. The right-hand side of `find | while`
  is a subshell; the counter it increments dies with it. This made one check
  silently incapable of failing.
- Lint through `.shellcheckrc`, never through an inline `-e` list. The suite used
  to carry its own copy, so it passed on findings CI rejected. There is one
  ruleset: the file.

The install and font tests use local fixtures rather than the network: an outage
must not read as a code regression.

## Shell style

Four spaces, no tabs. `bash -n` must pass on every script.

`.shellcheckrc` disables only `SC1090`, `SC1091`, `SC2034` and `SC2010`. It used
to disable `SC2086` and `SC2015` too, which hid real bugs — `SC2015`
(`A && B || C`) is the exact shape that made `clean.sh` report a skip as a
failure. If ShellCheck complains about a deliberate word-split over
`HYPRX_CONFIG_TARGETS`, annotate it with a reason; do not add the code to the
global disable list.

`bin/hyprx` has no `.sh` suffix, so `find -name '*.sh'` skips it. Both CI jobs
name it explicitly. Do not let that lapse.

**ShellCheck must be the same version everywhere.** CI downloads a pinned
ShellCheck from upstream rather than using `apt`, because the rule set moves
between releases: 0.11 is lenient about `A && B || C` where `B` is an
assignment, an older release is not. That gap is how twelve real findings passed
the suite and failed CI. Both jobs use the same `SHELLCHECK_VERSION`; bump it
deliberately and read the resulting diff.

**Never gate on a tool you have not declared.** `hyprx install` once aborted on
any minimal system — including the CI container — because the preflight gate
required `ping`, which lives in `iputils` and is in no package list here. The
probe itself was missing, and the gate read that as "no network". A missing probe
is *unknown*, not *down*, and unknown must never be fatal. If you add a check
that shells out, either declare the tool or give the check an explicit
"cannot verify" branch.

## Commit messages

Say what changed and why, and name the failure it prevents. The history here is
full of good examples — "doctor crashes on the healthy GBM case, false
'unreachable' on system services" is far more useful than "fix doctor".

## Reporting a bug

The output of `hyprx doctor` is the most useful single artifact. Include it,
along with your `packages.list` diff if you changed it.
