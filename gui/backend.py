"""Read-only data layer for the HyprX GUI.

Talks to the `hyprx` CLI and nothing else. No Qt imports live here on
purpose: the data layer stays testable on a machine with no Qt and no
display, which is what CI is.

Every call is read-only. Mutating commands belong to a later phase, and the
one thing this module must never grow is a method that changes system state
behind the user's back.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any, Iterator

_ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def strip_ansi(text: str) -> str:
    """Drop terminal colour codes.

    HyprX colours every diagnostic, and a raw escape sequence shown inside a
    Qt label renders as literal garbage rather than as text.
    """
    return _ANSI.sub("", text)

# The CLI is slow in places (doctor stats the disk and battery), so a generous
# ceiling that still refuses to hang the UI forever.
DEFAULT_TIMEOUT = 120.0

EVENT_PREFIX = "HYPRX_EVENT "
EVENT_SCHEMA = 1


class HyprxError(RuntimeError):
    """A CLI call failed, timed out, or returned something unusable."""


@dataclass(frozen=True)
class CliResult:
    rc: int
    stdout: str
    stderr: str

    @property
    def events(self) -> list[dict[str, Any]]:
        return list(parse_events(self.stderr))


def hyprx_bin() -> str:
    """Locate the installed CLI.

    Preference order is deliberate: an explicit HYPRX_BIN wins so a developer
    can point the GUI at a checkout, then the install symlink, then PATH.
    """
    explicit = os.environ.get("HYPRX_BIN")
    if explicit and os.path.isfile(explicit) and os.access(explicit, os.X_OK):
        return explicit

    installed = os.path.expanduser("~/.local/bin/hyprx")
    if os.path.isfile(installed) and os.access(installed, os.X_OK):
        return installed

    found = shutil.which("hyprx")
    if found:
        return found

    raise HyprxError(
        "hyprx not found. Install it with ./install.sh, or set HYPRX_BIN."
    )


def run_cli(
    *args: str, timeout: float = DEFAULT_TIMEOUT, check: bool = True
) -> CliResult:
    """Run one `hyprx` command.

    check=True raises HyprxError on a non-zero exit - for the JSON endpoints
    that means the document could not be produced at all. Endpoints that use a
    non-zero exit to mean "no data" (wallpaper current) pass check=False.
    """
    cmd = [hyprx_bin(), *args]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise HyprxError(f"{' '.join(args)}: timed out after {timeout:.0f}s") from exc
    except OSError as exc:
        raise HyprxError(f"{' '.join(args)}: cannot execute - {exc}") from exc

    if check and proc.returncode != 0:
        # Prefer a plain reason. stderr is where human warnings and the
        # HYPRX_EVENT stream land, and a green ANSI line is a terrible thing to
        # show a user as an error message - strip the escapes before using it.
        detail = [strip_ansi(line) for line in (proc.stderr or proc.stdout).splitlines()]
        detail = [line for line in detail if line.strip()]
        reason = detail[-1] if detail else f"exit {proc.returncode}"
        raise HyprxError(f"hyprx {' '.join(args)}: {reason}")

    return CliResult(proc.returncode, proc.stdout, proc.stderr)


def _json(
    args: tuple[str, ...], timeout: float = DEFAULT_TIMEOUT, allow_nonzero: bool = False
) -> Any:
    result = run_cli(*args, timeout=timeout, check=not allow_nonzero)
    text = result.stdout.strip()
    if not text:
        raise HyprxError(f"hyprx {' '.join(args)}: no output")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        # Prose on stdout is the classic failure here (see the doctor --json
        # stdout-pollution bug in REVIEW #28), so say what actually arrived
        # rather than only the parser's complaint.
        head = text.splitlines()[0][:120] if text else ""
        raise HyprxError(
            f"hyprx {' '.join(args)}: stdout was not JSON (starts: {head!r})"
        ) from exc


def parse_events(stream: str) -> Iterator[dict[str, Any]]:
    """Yield HYPRX_EVENT objects from a stderr stream.

    Non-event lines are the human log and are skipped here; a GUI keeps them
    for its "show log" pane so animation never hides output. A malformed
    event line is skipped rather than raising - one bad line must not cost the
    frontend the whole stream.
    """
    for line in stream.splitlines():
        if not line.startswith(EVENT_PREFIX):
            continue
        try:
            event = json.loads(line[len(EVENT_PREFIX):])
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            yield event


def doctor(timeout: float = DEFAULT_TIMEOUT) -> dict[str, Any]:
    """Health report. `hyprx doctor --json` already existed - it is the
    pattern every other endpoint copies.

    allow_nonzero because doctor exits 1 when it has warnings and 2 on bad
    usage, and BOTH still print a complete document on stdout - the exit code
    is the finding count, not a success flag. Treating exit 1 as failure would
    mean the dashboard could never show a machine that has warnings, which is
    most machines.
    """
    return _json(
        ("doctor", "--json", "--no-report"), timeout=timeout, allow_nonzero=True
    )


def config() -> dict[str, str]:
    """Every setting and its current value."""
    data = _json(("config", "list", "--json"), timeout=30.0)
    if not isinstance(data, dict):
        raise HyprxError("config list --json did not return an object")
    return {str(k): str(v) for k, v in data.items()}


def snapshots() -> list[dict[str, Any]]:
    """Rollback snapshots, newest last as the CLI sorts them."""
    data = _json(("rollback", "list", "--json"), timeout=30.0)
    if not isinstance(data, list):
        raise HyprxError("rollback list --json did not return a list")
    return [s for s in data if isinstance(s, dict)]


def wallpaper() -> str | None:
    """The live wallpaper path, or None when none is set.

    check=False because the endpoint exits non-zero for "no wallpaper" - that
    is an answer, not a failure.
    """
    result = run_cli("wallpaper", "current", "--json", check=False, timeout=30.0)
    text = result.stdout.strip()
    if not text:
        return None
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    value = data.get("wallpaper")
    return value if isinstance(value, str) and value else None


def findings_by_status(report: dict[str, Any]) -> dict[str, list[str]]:
    """Group doctor findings, worst first.

    A flat list of {status, detail} is fine for a terminal and useless for a
    dashboard: the eye wants "what is broken" first, not document order.
    """
    order = ("error", "warn", "ok")
    grouped: dict[str, list[str]] = {key: [] for key in order}
    for finding in report.get("findings", []):
        if not isinstance(finding, dict):
            continue
        status = str(finding.get("status", "ok"))
        detail = str(finding.get("detail", "")).strip()
        if not detail:
            continue
        grouped.setdefault(status, []).append(detail)
    return grouped