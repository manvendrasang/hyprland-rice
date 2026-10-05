"""Entry point: python -m gui

Kept tiny on purpose - argument handling and the Qt import live here, and the
import failure message is the one place a missing PySide6 can be explained
properly instead of tracebacking.
"""

from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="hyprx-gui",
        description="HyprX dashboard (read-only in this build).",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the CLI and the Qt toolkit, print what was found, then exit",
    )
    args = parser.parse_args(argv)

    try:
        import PySide6  # noqa: F401
    except ImportError:
        print(
            "PySide6 is not available to this interpreter.\n"
            "\n"
            "The GUI needs the system Python's PySide6. If you use pyenv, its\n"
            "shims shadow /usr/bin/python3, so install for the system one:\n"
            "    sudo pacman -S pyside6\n"
            "then run the launcher again - it selects an interpreter that has it.",
            file=sys.stderr,
        )
        return 2

    from . import backend

    if args.check:
        try:
            binary = backend.hyprx_bin()
        except backend.HyprxError as exc:
            print(f"CLI:  MISSING - {exc}", file=sys.stderr)
            return 1
        print(f"CLI:  {binary}")
        try:
            report = backend.doctor(timeout=30.0)
        except backend.HyprxError as exc:
            print(f"doctor: FAILED - {exc}", file=sys.stderr)
            return 1
        summary = report.get("summary", {})
        print(
            "doctor: ok "
            f"(errors={summary.get('errors', 0)} warnings={summary.get('warnings', 0)})"
        )
        import PySide6

        print(f"Qt:    PySide6 {PySide6.__version__}")
        return 0

    from .window import run

    return run()


if __name__ == "__main__":
    sys.exit(main())