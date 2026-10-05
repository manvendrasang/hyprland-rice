"""Main window: title bar, tabs, refresh.

Refresh is manual plus an optional timer. Read-only tabs never mutate, so
auto-refresh cannot do damage - but it is off by default because a dashboard
that re-runs `doctor` (which stats the disk and reads the battery) every few
seconds is wasteful, and the user should see when data was fetched.
"""

from __future__ import annotations

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from . import backend, theme
from .tabs import OverviewTab, SettingsTab, SnapshotsTab, WallpaperTab

REFRESH_CHOICES = (0, 15, 30, 60, 300)


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("HyprX")
        self.resize(940, 660)

        self.accent = theme.accent()
        self.setStyleSheet(theme.stylesheet(self.accent))

        central = QWidget()
        outer = QVBoxLayout(central)
        outer.setContentsMargins(16, 14, 16, 14)
        outer.setSpacing(12)

        header = QHBoxLayout()
        title = QLabel("HyprX")
        title.setObjectName("H1")
        subtitle = QLabel("read-only dashboard")
        subtitle.setObjectName("Dim")
        header.addWidget(title)
        header.addWidget(subtitle)
        header.addStretch(1)

        self.refresh_button = QPushButton("Refresh")
        self.refresh_button.setToolTip("Re-read every tab")
        self.refresh_button.clicked.connect(self.refresh_all)
        header.addWidget(self.refresh_button)

        self.auto_button = QPushButton("Auto: off")
        self.auto_button.setToolTip(
            "Re-read every tab on an interval.\n"
            "Read-only tabs, so this cannot change anything."
        )
        self.auto_button.clicked.connect(self._cycle_auto)
        header.addWidget(self.auto_button)

        self.reload_theme_button = QPushButton("Theme")
        self.reload_theme_button.setToolTip(
            "Re-read the accent from the live HyprX theme"
        )
        self.reload_theme_button.clicked.connect(self._reload_theme)
        header.addWidget(self.reload_theme_button)

        outer.addLayout(header)

        self.tabs = QTabWidget()
        self.overview = OverviewTab()
        self.settings = SettingsTab()
        self.snapshots = SnapshotsTab()
        self.wallpaper = WallpaperTab()
        for widget, name in (
            (self.overview, "Overview"),
            (self.settings, "Settings"),
            (self.snapshots, "Snapshots"),
            (self.wallpaper, "Wallpaper"),
        ):
            self.tabs.addTab(widget, name)
        outer.addWidget(self.tabs, 1)

        self.setCentralWidget(central)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.refresh_all)
        self._auto_index = 0

        self.refresh_all()

    def _cycle_auto(self) -> None:
        self._auto_index = (self._auto_index + 1) % len(REFRESH_CHOICES)
        seconds = REFRESH_CHOICES[self._auto_index]
        if seconds:
            self._timer.start(seconds * 1000)
            self.auto_button.setText(f"Auto: {seconds // 60 or seconds}s")
        else:
            self._timer.stop()
            self.auto_button.setText("Auto: off")

    def _reload_theme(self) -> None:
        """Pick up a wallpaper change: the accent follows colors.conf."""
        self.accent = theme.accent()
        self.setStyleSheet(theme.stylesheet(self.accent))

    def refresh_all(self) -> None:
        # Only the visible tab is loaded. Refreshing hidden tabs costs four
        # subprocesses nobody is looking at.
        self.tabs.currentWidget().load()


def run() -> int:
    from PySide6.QtWidgets import QApplication

    app = QApplication.instance() or QApplication([])
    app.setApplicationName("HyprX")

    window = MainWindow()
    window.show()

    try:
        backend.doctor(timeout=10.0)
    except backend.HyprxError:
        # The window already renders its own error state; nothing to add, and
        # raising here would mean no window at all.
        pass

    return app.exec()