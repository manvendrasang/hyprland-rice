"""Colours for the GUI.

The accent is read from the LIVE HyprX theme (~/.config/hypr/colors.conf,
written by wallust on every wallpaper change) so the window matches the bar
the user is already looking at. That file may be absent, half-written by a
wallust run, or not a valid colour, so every read is best-effort and the
fallback palette is a complete theme on its own - the GUI must never fail to
paint because a wallpaper is mid-change.
"""

from __future__ import annotations

import os
import re

# Fixed dark palette. Chosen to read well on any wallpaper-derived accent.
BG = "#12141a"
SURFACE = "#1a1d26"
SURFACE_HI = "#232733"
BORDER = "#2c3140"
FG = "#e6e8ef"
FG_DIM = "#9aa0b0"
ACCENT = "#61afef"      # One Dark blue, the shipped one-dark default
OK = "#98c379"
WARN = "#e5c07b"
ERROR = "#e06c75"

_HEX = re.compile(r"^#?([0-9a-fA-F]{6})\s*$")
_KEY = re.compile(r"^\s*\$?([A-Za-z0-9_]+)\s*=\s*(.+?)\s*$")


def _read_conf(path: str) -> dict[str, str]:
    """Parse a flat key = value conf file. Duplicates: last wins."""
    values: dict[str, str] = {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                stripped = line.split("#", 1)[0].strip()
                if not stripped:
                    continue
                match = _KEY.match(stripped)
                if match:
                    values[match.group(1)] = match.group(2)
    except OSError:
        return {}
    return values


def _as_hex(value: str | None) -> str | None:
    if not value:
        return None
    # rgba()/rgb() forms carry alpha, which a background cannot take here.
    match = _HEX.match(value.split("(")[0].split(",")[0].strip())
    return f"#{match.group(1)}" if match else None


def accent(default: str = ACCENT) -> str:
    """The live accent colour, or the default when unreadable."""
    path = os.path.expanduser("~/.config/hypr/colors.conf")
    conf = _read_conf(path)
    for key in ("color12", "active_border", "color0"):
        candidate = _as_hex(conf.get(key))
        if candidate:
            return candidate
    return default


def stylesheet(accent_colour: str | None = None) -> str:
    """Application stylesheet.

    One accent variable threaded through every rule that uses it, so a
    wallpaper change only has to change one string.
    """
    accent_colour = accent_colour or accent()
    return f"""
    QWidget {{
        background: {BG};
        color: {FG};
        font-size: 13px;
    }}
    QTabWidget::pane {{
        border: 1px solid {BORDER};
        border-radius: 8px;
        top: -1px;
    }}
    QTabBar::tab {{
        background: transparent;
        color: {FG_DIM};
        padding: 8px 18px;
        border: none;
        border-bottom: 2px solid transparent;
    }}
    QTabBar::tab:selected {{
        color: {FG};
        border-bottom: 2px solid {accent_colour};
    }}
    QTabBar::tab:hover:!selected {{ color: {FG}; }}
    QTableWidget {{
        background: {SURFACE};
        alternate-background-color: {SURFACE_HI};
        gridline-color: {BORDER};
        border: none;
        selection-background-color: {accent_colour}33;
        selection-color: {FG};
    }}
    QHeaderView::section {{
        background: {SURFACE_HI};
        color: {FG_DIM};
        padding: 6px 8px;
        border: none;
        border-bottom: 1px solid {BORDER};
        font-weight: 600;
    }}
    QListWidget {{
        background: {SURFACE};
        border: none;
        border-radius: 6px;
        outline: none;
    }}
    QListWidget::item {{ padding: 6px 10px; border-radius: 6px; }}
    QListWidget::item:selected {{ background: {SURFACE_HI}; }}
    QLabel#H1 {{ font-size: 20px; font-weight: 700; }}
    QLabel#Dim {{ color: {FG_DIM}; }}
    QLabel#Card {{
        background: {SURFACE};
        border: 1px solid {BORDER};
        border-radius: 10px;
    }}
    QPushButton {{
        background: {SURFACE_HI};
        color: {FG};
        border: 1px solid {BORDER};
        border-radius: 6px;
        padding: 6px 14px;
    }}
    QPushButton:hover {{ border-color: {accent_colour}; }}
    QPushButton:disabled {{ color: {FG_DIM}; border-color: {BORDER}; }}
    QScrollBar:vertical {{ background: transparent; width: 10px; margin: 0; }}
    QScrollBar::handle:vertical {{
        background: {BORDER}; border-radius: 5px; min-height: 30px;
    }}
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
    QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{ background: none; }}
    """


def status_colour(status: str) -> str:
    return {"ok": OK, "warn": WARN, "error": ERROR}.get(status, FG_DIM)