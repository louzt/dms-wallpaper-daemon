#!/usr/bin/env python3
"""Adversarial tests for parse_args + fallback_image_for_candidate.

Targets the bug class where:
- argparse defaults regress after a flag rename (e.g. F-2 audit case
  where body said default=3 but code had default=1).
- fallback_image_for_candidate returns a non-image path that would
  crash swww later.
- apply_static_fallback early-return paths behave predictably when
  swww is unavailable.
"""

import sys
import argparse
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "waypaper-video-random"

import importlib.machinery
import importlib.util


def _load_script_module():
    loader = importlib.machinery.SourceFileLoader("wallpaper_script", str(SCRIPT))
    spec = importlib.util.spec_from_loader("wallpaper_script", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules["wallpaper_script"] = mod
    loader.exec_module(mod)
    return mod


class ParseArgsDefaultsTests(unittest.TestCase):
    """Regression guard for F-2 audit finding: body-vs-code default drift."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_script_module()

    def test_default_max_fixed_playlist_attempts_post_F2(self) -> None:
        """After F-2 amend, default must be 3 (not 1)."""
        # Patch sys.argv so parse_args reads only the default flags.
        saved = sys.argv
        sys.argv = ["waypaper-video-random"]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertEqual(
            args.max_fixed_playlist_attempts,
            3,
            "max-fixed-playlist-attempts default regressed; should be 3 after F-2",
        )

    def test_default_max_retries_is_2(self) -> None:
        """Default max-retries must stay at 2 (canonical, was correct in body)."""
        saved = sys.argv
        sys.argv = ["waypaper-video-random"]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertEqual(args.max_retries, 2)

    def test_default_mode_is_video(self) -> None:
        """Default --mode must be 'video' (not 'smart' or 'all')."""
        saved = sys.argv
        sys.argv = ["waypaper-video-random"]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertEqual(args.mode, "video")

    def test_default_allow_all_is_false(self) -> None:
        """--allow-all must default to False for safety."""
        saved = sys.argv
        sys.argv = ["waypaper-video-random"]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertFalse(args.allow_all)

    def test_mode_choices_reject_invalid(self) -> None:
        """--mode must reject values outside {video, smart, all}."""
        saved = sys.argv
        sys.argv = ["waypaper-video-random", "--mode", "potato"]
        try:
            with self.assertRaises(SystemExit):
                self.mod.parse_args()
        finally:
            sys.argv = saved

    def test_max_fixed_playlist_attempts_custom(self) -> None:
        """--max-fixed-playlist-attempts accepts int overrides."""
        saved = sys.argv
        sys.argv = [
            "waypaper-video-random",
            "--max-fixed-playlist-attempts",
            "10",
        ]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertEqual(args.max_fixed_playlist_attempts, 10)

    def test_fallback_wallpaper_accepts_path(self) -> None:
        """--fallback-wallpaper accepts a Path and is None by default."""
        saved = sys.argv
        sys.argv = ["waypaper-video-random"]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertIsNone(args.fallback_wallpaper)
        saved = sys.argv
        sys.argv = [
            "waypaper-video-random",
            "--fallback-wallpaper",
            "/tmp/fallback.jpg",
        ]
        try:
            args = self.mod.parse_args()
        finally:
            sys.argv = saved
        self.assertEqual(args.fallback_wallpaper, Path("/tmp/fallback.jpg"))


class FallbackImageForCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_script_module()

    def test_returns_none_when_nothing_available(self) -> None:
        """No configured fallback, no candidate image, no preview → None."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj-1"
            project.mkdir()
            video = project / "scene.mp4"
            video.write_bytes(b"")
            cand = self.mod.Candidate(
                project_dir=project,
                wallpaper_path=video,
                title="Scene",
                wallpaper_type="video",
                width=1920,
                height=1080,
                duration=10.0,
                tags=(),
            )
            result = self.mod.fallback_image_for_candidate(cand, None)
            self.assertIsNone(result)

    def test_returns_configured_fallback_when_image_exists(self) -> None:
        """Configured --fallback-wallpaper that exists with static suffix wins."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj-2"
            project.mkdir()
            video = project / "scene.mp4"
            video.write_bytes(b"")
            cand = self.mod.Candidate(
                project_dir=project,
                wallpaper_path=video,
                title="Scene",
                wallpaper_type="video",
                width=1920,
                height=1080,
                duration=10.0,
                tags=(),
            )
            cfg = Path(tmp) / "fallback.png"
            cfg.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            result = self.mod.fallback_image_for_candidate(cand, cfg)
            self.assertEqual(result, cfg)

    def test_rejects_configured_fallback_with_non_image_suffix(self) -> None:
        """Configured fallback with .mp4 suffix must NOT be chosen."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj-3"
            project.mkdir()
            cand = self.mod.Candidate(
                project_dir=project,
                wallpaper_path=Path("/nonexistent"),
                title="x",
                wallpaper_type="video",
                width=None,
                height=None,
                duration=None,
                tags=(),
            )
            cfg = Path(tmp) / "wrong.mp4"
            cfg.write_bytes(b"")
            result = self.mod.fallback_image_for_candidate(cand, cfg)
            self.assertIsNone(result)

    def test_falls_back_to_preview_png(self) -> None:
        """When candidate is video and no configured fallback, falls back to preview.png."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj-4"
            project.mkdir()
            video = project / "scene.mp4"
            video.write_bytes(b"")
            preview = project / "preview.png"
            preview.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            cand = self.mod.Candidate(
                project_dir=project,
                wallpaper_path=video,
                title="x",
                wallpaper_type="video",
                width=1920,
                height=1080,
                duration=10.0,
                tags=(),
            )
            result = self.mod.fallback_image_for_candidate(cand, None)
            self.assertEqual(result, preview)

    def test_falls_back_to_preview_jpg(self) -> None:
        """jpg preview is also accepted."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj-5"
            project.mkdir()
            video = project / "scene.mp4"
            video.write_bytes(b"")
            preview = project / "preview.jpg"
            preview.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 16)
            cand = self.mod.Candidate(
                project_dir=project,
                wallpaper_path=video,
                title="x",
                wallpaper_type="video",
                width=1920,
                height=1080,
                duration=10.0,
                tags=(),
            )
            result = self.mod.fallback_image_for_candidate(cand, None)
            self.assertEqual(result, preview)


class ApplyStaticFallbackEarlyReturnTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_script_module()

    def test_returns_none_when_no_fallback_path(self) -> None:
        """apply_static_fallback returns None when no fallback image is found."""
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj-nofb"
            project.mkdir()
            video = project / "scene.mp4"
            video.write_bytes(b"")
            cand = self.mod.Candidate(
                project_dir=project,
                wallpaper_path=video,
                title="x",
                wallpaper_type="video",
                width=1920,
                height=1080,
                duration=10.0,
                tags=(),
            )
            args = argparse.Namespace(fallback_wallpaper=None, dry_run=False)
            result = self.mod.apply_static_fallback(cand, "HDMI-A-1", args, verbose=False)
            self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
