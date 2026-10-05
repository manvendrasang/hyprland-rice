"""The four read-only tabs.

Each tab owns one backend call, keeps its last good data on refresh failure
(a dashboard that empties itself because one CLI call timed out is worse than
a stale one - the user cannot tell "broken" from "not loaded"), and never
mutates anything.
"""

from __future__ import annotations

import os
import time
from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QPixmap
from PySide6.QtWidgets import (
    QAbstractItemView,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from . import backend, theme


class _Tab(QWidget):
    """Shared refresh plumbing: one loader, one error label, stale-on-fail."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._last_ok: Any = None
        self._loaded_at: float | None = None

        self.status = QLabel("")
        self.status.setObjectName("Dim")

    def load(self) -> None:
        try:
            data = self.fetch()
        except backend.HyprxError as exc:
            when = (
                time.strftime("%H:%M:%S", time.localtime(self._loaded_at))
                if self._loaded_at
                else "never"
            )
            self.status.setText(f"Could not refresh: {exc}  (showing data from {when})")
            self.status.setStyleSheet(f"color: {theme.ERROR};")
            return

        self._last_ok = data
        self._loaded_at = time.time()
        self.render(data)
        self.status.setText(f"Updated {time.strftime('%H:%M:%S')}")
        self.status.setStyleSheet(f"color: {theme.FG_DIM};")

    def fetch(self) -> Any:  # pragma: no cover - implemented by subclasses
        raise NotImplementedError

    def render(self, data: Any) -> None:  # pragma: no cover
        raise NotImplementedError


def _card(title: str, colour: str) -> tuple[QFrame, QLabel]:
    """A tally tile. Returns the value label so the caller can set it
    directly - reaching back into the frame for it worked, then stopped
    working the moment a second label was added."""
    frame = QFrame()
    frame.setObjectName("Card")
    layout = QVBoxLayout(frame)
    layout.setContentsMargins(16, 12, 16, 12)
    layout.setSpacing(2)
    # Top-aligned: a QGridLayout cell is taller than the two labels need, and
    # the default distribution floats the pair apart - the number then sits at a
    # different height than its neighbours in the row.
    layout.setAlignment(Qt.AlignmentFlag.AlignTop)

    caption = QLabel(title)
    caption.setObjectName("Dim")
    number = QLabel("-")
    number.setStyleSheet(f"font-size: 26px; font-weight: 700; color: {colour};")
    layout.addWidget(caption)
    layout.addWidget(number)
    return frame, number


class OverviewTab(_Tab):
    """Health at a glance: tallies, suggestions, and every finding.

    Findings worst-first, and the ok ones folded away by default - 61 green
    rows is noise on a screen whose job is to answer "is anything wrong".
    """

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        outer = QVBoxLayout(self)
        outer.setSpacing(12)

        self.cards = QGridLayout()
        self.cards.setSpacing(10)
        err_frame, self.value_errors = _card("Errors", theme.ERROR)
        warn_frame, self.value_warnings = _card("Warnings", theme.WARN)
        ok_frame, self.value_passed = _card("Checks passed", theme.OK)
        for column, frame in enumerate((err_frame, warn_frame, ok_frame)):
            self.cards.addWidget(frame, 0, column)
        outer.addLayout(self.cards)

        self.host = QLabel("")
        self.host.setObjectName("Dim")
        outer.addWidget(self.host)

        self.suggestions = QLabel("")
        self.suggestions.setWordWrap(True)
        self.suggestions.setStyleSheet(f"color: {theme.WARN};")
        self.suggestions.setVisible(False)
        outer.addWidget(self.suggestions)

        self.findings = QListWidget()
        self.findings.setAlternatingRowColors(False)
        outer.addWidget(self.findings, 1)

    def fetch(self) -> dict[str, Any]:
        return backend.doctor()

    def render(self, report: dict[str, Any]) -> None:
        summary = report.get("summary", {})
        if not isinstance(summary, dict):
            summary = {}
        errors = int(summary.get("errors", 0) or 0)
        warnings = int(summary.get("warnings", 0) or 0)

        grouped = backend.findings_by_status(report)
        passed = len(grouped.get("ok", []))

        self.value_errors.setText(str(errors))
        self.value_warnings.setText(str(warnings))
        self.value_passed.setText(str(passed))

        uptime = report.get("uptime_seconds")
        bits = [
            str(report.get("distro", "?")),
            f"kernel {report.get('kernel', '?')}",
            str(report.get("session", "?")),
        ]
        if isinstance(uptime, (int, float)) and uptime > 0:
            days, rem = divmod(int(uptime), 86400)
            hours = rem // 3600
            bits.append(f"up {days}d {hours}h")
        self.host.setText("  ·  ".join(bits))

        suggestions = report.get("suggestions") or []
        if isinstance(suggestions, list) and suggestions:
            self.suggestions.setText("Suggested:  " + "   ·   ".join(map(str, suggestions)))
            self.suggestions.setVisible(True)
        else:
            self.suggestions.setVisible(False)

        self.findings.clear()
        # Worst first. ok entries stay listed but recede, so nothing is hidden
        # - the list is ordered by what needs reading, not filtered by it.
        for status in ("error", "warn", "ok"):
            colour = QColor(theme.status_colour(status))
            if status == "ok":
                colour.setAlpha(140)
            for detail in grouped.get(status, []):
                item = QListWidgetItem(f"●  {detail}")
                item.setForeground(colour)
                self.findings.addItem(item)


class SettingsTab(_Tab):
    """Every setting and its value. Read-only by construction in this phase."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        outer = QVBoxLayout(self)
        outer.setSpacing(8)

        hint = QLabel("Read-only in this build. Use `hyprx config set KEY VALUE` to change.")
        hint.setObjectName("Dim")
        outer.addWidget(hint)

        self.table = QTableWidget(0, 2)
        self.table.setHorizontalHeaderLabels(["Setting", "Value"])
        self.table.verticalHeader().setVisible(False)
        self.table.setAlternatingRowColors(True)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        outer.addWidget(self.table, 1)

    def fetch(self) -> dict[str, str]:
        return backend.config()

    def render(self, values: dict[str, str]) -> None:
        self.table.setRowCount(len(values))
        for row, (key, value) in enumerate(values.items()):
            self.table.setItem(row, 0, QTableWidgetItem(key))
            item = QTableWidgetItem(value or "(unset)")
            if not value:
                item.setForeground(Qt.GlobalColor.gray)
            self.table.setItem(row, 1, item)


class SnapshotsTab(_Tab):
    """Rollback snapshots with their package and config counts."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        outer = QVBoxLayout(self)
        outer.setSpacing(8)

        hint = QLabel("Read-only in this build. `hyprx rollback list` to act.")
        hint.setObjectName("Dim")
        outer.addWidget(hint)

        self.table = QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["Snapshot", "When", "Packages", "Configs"])
        self.table.verticalHeader().setVisible(False)
        self.table.setAlternatingRowColors(True)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        outer.addWidget(self.table, 1)

    def fetch(self) -> list[dict[str, Any]]:
        return backend.snapshots()

    def render(self, snapshots: list[dict[str, Any]]) -> None:
        self.table.setRowCount(len(snapshots))
        for row, snap in enumerate(snapshots):
            self.table.setItem(row, 0, QTableWidgetItem(str(snap.get("id", "?"))))
            self.table.setItem(row, 1, QTableWidgetItem(str(snap.get("date", ""))))
            self.table.setItem(
                row, 2, QTableWidgetItem(str(snap.get("packages", 0)))
            )
            self.table.setItem(
                row, 3, QTableWidgetItem(str(snap.get("configs", 0)))
            )


class WallpaperTab(_Tab):
    """The live wallpaper, as a thumbnail plus its path.

    This is the tab that makes the wallust pipeline visible: the picture
    changes here the moment the bar's colours change.
    """

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        outer = QVBoxLayout(self)
        outer.setSpacing(10)

        self.preview = QLabel("No wallpaper set.")
        self.preview.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview.setMinimumHeight(280)
        self.preview.setStyleSheet(
            f"color: {theme.FG_DIM}; background: {theme.SURFACE};"
            "border: 1px solid " + theme.BORDER + "; border-radius: 10px;"
        )
        outer.addWidget(self.preview, 1)

        self.path = QLabel("")
        self.path.setObjectName("Dim")
        self.path.setWordWrap(True)
        self.path.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        outer.addWidget(self.path)

    def fetch(self) -> str | None:
        return backend.wallpaper()

    def render(self, path: str | None) -> None:
        if not path or not os.path.isfile(path):
            self.preview.setText("No wallpaper set.")
            self.preview.setPixmap(QPixmap())
            self.path.setText(path or "")
            return

        pixmap = QPixmap(path)
        if pixmap.isNull():
            self.preview.setText("Could not read the image.")
            self.path.setText(path)
            return

        self.preview.setPixmap(
            pixmap.scaled(
                self.preview.size(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
        )
        self.path.setText(os.path.dirname(path))