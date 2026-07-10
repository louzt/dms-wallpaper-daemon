#!/usr/bin/env python3
"""Synthetic tests for waypaper-video-random write_override_file.

Covers the four branches the self-heal QML plugin depends on:
  - no-renderer : nothing in /proc matches -> entry removed
  - live        : matching renderer in /proc -> live entry written
  - mixed       : some live, some not
  - quarantine  : returncode != 0 -> quarantine entry written

Run from the plugin repo root:
    python3 -m unittest tests/test_write_override_file.py -v

The tests use a tmp_path for OVERRIDE_PATH and monkey-patch the
module-level constant so they never touch the user's real
~/.local/state/lzt/wallpaper-override.json.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "waypaper-video-random"


def _load_script_module() -> Any:
    """Load waypaper-video-random as a module.

    The script has no `.py` extension, so we use SourceFileLoader
    directly; importlib.util.spec_from_file_location refuses files
    without a recognised suffix and returns None. The module also
    must be in sys.modules before exec_module so the @dataclass
    decorator can resolve cls.__module__.__dict__.
    """
    sys.argv = ["waypaper-video-random", "--list"]
    from importlib.machinery import SourceFileLoader
    loader = SourceFileLoader("waypaper_video_random", str(SCRIPT))
    spec = importlib.util.spec_from_loader("waypaper_video_random", loader)
    if spec is None:
        raise RuntimeError(f"cannot build spec for {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["waypaper_video_random"] = module
    loader.exec_module(module)
    return module


class WriteOverrideFileTests(unittest.TestCase):
    mod: Any  # populated in setUpClass; typed to keep pyright quiet

    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_script_module()

    def setUp(self) -> None:
        # Per-test override path so writes never hit the real file
        self.tmp = self._make_tmp()
        self._patcher = mock.patch.object(self.mod, "OVERRIDE_PATH", self.tmp)
        self._patcher.start()

    def tearDown(self) -> None:
        self._patcher.stop()
        if self.tmp.exists():
            self.tmp.unlink()

    @staticmethod
    def _make_tmp() -> Path:
        import tempfile
        fd, name = tempfile.mkstemp(prefix="wallpaper-override-", suffix=".json")
        os.close(fd)
        path = Path(name)
        path.unlink()  # start with no file
        return path

    def _read(self) -> dict:
        return json.loads(self.tmp.read_text(encoding="utf-8"))

    def _seed_existing(self, payload: dict) -> None:
        self.tmp.parent.mkdir(parents=True, exist_ok=True)
        self.tmp.write_text(json.dumps(payload), encoding="utf-8")

    # --- branch: no-renderer ---
    def test_no_renderer_removes_entry(self) -> None:
        self._seed_existing({
            "version": 1,
            "overrides": {
                "HDMI-A-1": {"backend": "linux-wallpaperengine", "pid": 999999, "since": 1},
            },
        })
        # No process in /proc matches monitor "HDMI-A-1"
        with mock.patch.object(self.mod, "find_renderer", return_value=None):
            self.mod.write_override_file([{"monitor": "HDMI-A-1", "returncode": 0}])
        payload = self._read()
        self.assertNotIn("HDMI-A-1", payload["overrides"])

    # --- branch: live ---
    def test_live_entry_written(self) -> None:
        with mock.patch.object(
            self.mod, "find_renderer", return_value=("linux-wallpaperengine", 4242)
        ):
            self.mod.write_override_file([
                {"monitor": "HDMI-A-1", "returncode": 0, "project": "we:abc", "type": "video"}
            ])
        payload = self._read()
        entry = payload["overrides"]["HDMI-A-1"]
        self.assertEqual(entry["backend"], "linux-wallpaperengine")
        self.assertEqual(entry["pid"], 4242)
        self.assertEqual(entry["project"], "we:abc")
        self.assertEqual(entry["type"], "video")
        self.assertIn("since", entry)

    # --- branch: mixed ---
    def test_mixed_keeps_live_drops_missing(self) -> None:
        self._seed_existing({
            "version": 1,
            "overrides": {
                "HDMI-A-1": {"backend": "linux-wallpaperengine", "pid": 1000, "since": 1},
                "DP-1":     {"backend": "linux-wallpaperengine", "pid": 2000, "since": 1},
            },
        })
        def fake_find(monitor: str):
            if monitor == "HDMI-A-1":
                return ("linux-wallpaperengine", 1000)
            return None  # DP-1 has no live renderer
        with mock.patch.object(self.mod, "find_renderer", side_effect=fake_find):
            self.mod.write_override_file([
                {"monitor": "HDMI-A-1", "returncode": 0},
                {"monitor": "DP-1", "returncode": 0},
            ])
        payload = self._read()
        self.assertIn("HDMI-A-1", payload["overrides"])
        self.assertNotIn("DP-1", payload["overrides"])

    # --- branch: quarantine ---
    def test_quarantine_entry_written_on_nonzero(self) -> None:
        self.mod.write_override_file([{
            "monitor": "HDMI-A-1",
            "returncode": -11,  # SIGSEGV from PulseAudio
            "quarantine_reason": "pulseaudio_sigsegv",
            "project": "we:bad",
        }])
        payload = self._read()
        entry = payload["overrides"]["HDMI-A-1"]
        self.assertEqual(entry["backend"], "quarantine")
        self.assertEqual(entry["pid"], 0)
        self.assertEqual(entry["quarantine_reason"], "pulseaudio_sigsegv")
        self.assertEqual(entry["quarantine_code"], -11)
        self.assertIn("quarantine_since", entry)

    # --- atomic write: chmod 600 ---
    def test_atomic_write_sets_600(self) -> None:
        with mock.patch.object(
            self.mod, "find_renderer", return_value=("linux-wallpaperengine", 4242)
        ):
            self.mod.write_override_file([{"monitor": "HDMI-A-1", "returncode": 0}])
        mode = self.tmp.stat().st_mode & 0o777
        self.assertEqual(mode, 0o600, f"expected 0o600, got {oct(mode)}")

    # --- empty input is a no-op ---
    def test_empty_results_does_not_touch_file(self) -> None:
        self._seed_existing({"version": 1, "overrides": {"X": {"backend": "b", "pid": 1, "since": 1}}})
        self.mod.write_override_file([])
        # File should be untouched (still has "X")
        self.assertIn("X", self._read()["overrides"])

    # --- monitor name blank is skipped ---
    def test_blank_monitor_skipped(self) -> None:
        self._seed_existing({"version": 1, "overrides": {}})
        with mock.patch.object(
            self.mod, "find_renderer", return_value=("linux-wallpaperengine", 1)
        ) as fr:
            self.mod.write_override_file([{"monitor": "  ", "returncode": 0}])
        fr.assert_not_called()
        self.assertEqual(self._read()["overrides"], {})


if __name__ == "__main__":
    unittest.main(verbosity=2)
