#!/usr/bin/env python3
"""Adversarial tests for find_renderer / _renderer_backend_for_args.

Targets the bug class where output_name is treated as a literal
subprocess argument without sanitization, which could allow process
matching on poisoned argv (e.g. an attacker who plants a process
named `--screen-root HDMI-A-1` masquerading as the user's monitor).
"""

import sys
import unittest
from pathlib import Path

# Make the parent directory importable so we can load the script.
HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "waypaper-video-random"

import importlib.machinery
import importlib.util


def _load_script_module():
    loader = importlib.machinery.SourceFileLoader("wallpaper_script", str(SCRIPT))
    spec = importlib.util.spec_from_loader("wallpaper_script", loader)
    assert spec is not None, f"spec_from_loader returned None for {SCRIPT}"
    mod = importlib.util.module_from_spec(spec)
    sys.modules["wallpaper_script"] = mod
    loader.exec_module(mod)
    return mod


class FindRendererTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_script_module()

    def test_backend_match_exact_screen_root(self) -> None:
        """Standard case: lwe process with --screen-root <output> matches."""
        mod = self.mod
        args = [
            "/usr/bin/linux-wallpaperengine",
            "--screen-root",
            "HDMI-A-1",
            "--no-audio-processing",
        ]
        result = mod._renderer_backend_for_args(args, "HDMI-A-1")
        self.assertEqual(result, "linux-wallpaperengine")

    def test_backend_match_mpvpaper_substring(self) -> None:
        """mpvpaper matches by name appearing anywhere in argv."""
        mod = self.mod
        args = [
            "/usr/bin/mpvpaper",
            "-o",
            "DP-1",
            "/path/to/wallpaper.mp4",
        ]
        result = mod._renderer_backend_for_args(args, "DP-1")
        self.assertEqual(result, "mpvpaper")

    def test_backend_reject_wrong_output(self) -> None:
        """lwe process for HDMI-A-1 should NOT match query for eDP-1."""
        mod = self.mod
        args = [
            "/usr/bin/linux-wallpaperengine",
            "--screen-root",
            "HDMI-A-1",
        ]
        self.assertIsNone(mod._renderer_backend_for_args(args, "eDP-1"))
        self.assertIsNone(mod._renderer_backend_for_args(args, "DP-1"))
        self.assertIsNone(mod._renderer_backend_for_args(args, ""))

    def test_backend_reject_empty_args(self) -> None:
        """Empty argv never matches."""
        mod = self.mod
        self.assertIsNone(mod._renderer_backend_for_args([], "HDMI-A-1"))
        self.assertIsNone(mod._renderer_backend_for_args([""], "HDMI-A-1"))

    def test_backend_reject_unknown_backend(self) -> None:
        """Other renderer binaries (swww-daemon, mpv, etc.) don't match."""
        mod = self.mod
        for exe in [
            "/usr/bin/swww-daemon",
            "/usr/bin/mpv",
            "/usr/bin/waypaper",
            "/usr/bin/bash",
            "/usr/bin/python3",
        ]:
            result = mod._renderer_backend_for_args([exe, "HDMI-A-1"], "HDMI-A-1")
            self.assertIsNone(
                result,
                f"backend with executable={exe} should not match",
            )

    def test_backend_reject_equals_form(self) -> None:
        """`--screen-root=HDMI-A-1` (equals form) should also match."""
        mod = self.mod
        args = [
            "/usr/bin/linux-wallpaperengine",
            "--screen-root=HDMI-A-1",
        ]
        self.assertEqual(
            mod._renderer_backend_for_args(args, "HDMI-A-1"), "linux-wallpaperengine"
        )

    def test_backend_reject_partial_arg_no_value(self) -> None:
        """`--screen-root` with no following value should not match."""
        mod = self.mod
        args = [
            "/usr/bin/linux-wallpaperengine",
            "--screen-root",
        ]
        self.assertIsNone(mod._renderer_backend_for_args(args, "HDMI-A-1"))

    def test_backend_reject_empty_executable_name(self) -> None:
        """argv[0] of empty string (process with no exec name) shouldn't match."""
        mod = self.mod
        args = ["", "--screen-root", "HDMI-A-1"]
        # Path(args[0]).name == "" → not "linux-wallpaperengine"
        self.assertIsNone(mod._renderer_backend_for_args(args, "HDMI-A-1"))

    def test_backend_reject_substring_in_other_arg(self) -> None:
        """`HDMI-A-1` appearing in a non-flag arg should not match lwe."""
        mod = self.mod
        # The output name is in a non-flag positional arg, not as the value
        # of --screen-root. Must not match.
        args = [
            "/usr/bin/linux-wallpaperengine",
            "HDMI-A-1-some-folder",
        ]
        self.assertIsNone(mod._renderer_backend_for_args(args, "HDMI-A-1"))

    def test_find_renderer_returns_none_when_no_proc_match(self) -> None:
        """find_renderer() returns None when no /proc/<pid> matches."""
        mod = self.mod

        # Patch Path.iterdir via the function's own module reference.
        class _FakeProc:
            def __init__(self, name: str):
                self.name = name

        fake_entries = [
            _FakeProc("cpuinfo"),       # not a digit
            _FakeProc("loadavg"),       # not a digit
        ]

        original_iterdir = Path.iterdir
        Path.iterdir = lambda _: iter(fake_entries)  # type: ignore[assignment]
        try:
            result = mod.find_renderer("HDMI-A-1")
        finally:
            Path.iterdir = original_iterdir
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
