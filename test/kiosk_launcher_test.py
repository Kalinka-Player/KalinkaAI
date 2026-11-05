"""Exercise panel permission and restore handling without touching real hardware."""
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch


class KioskLauncherTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.backlights = self.root / "backlights"
        self.backlights.mkdir()
        self.module = runpy.run_path(
            str(Path(__file__).resolve().parents[1] / "packaging/kiosk/kalinka-kiosk-ctl")
        )
        self.state = self.module["prepare"].__globals__
        self.state["RUN_DIR"] = str(self.root)
        self.state["BACKLIGHT_DIR"] = self.backlights

    def panel(self, name="panel", kind="raw"):
        directory = self.backlights / name
        directory.mkdir()
        (directory / "type").write_text(kind)
        control = directory / "bl_power"
        control.write_text("0")
        return control

    def test_prepare_launch_and_crash_restore(self):
        control = self.panel()
        self.state["_overrides"] = lambda: {"base_config.display.enabled": True}
        with patch.object(self.module["os"], "chown") as ownership:
            self.module["prepare"]()
        ownership.assert_called_once()
        self.assertTrue(control.stat().st_mode & 0o020)
        with patch.object(self.module["os"], "execve") as launch:
            self.module["run"]()
        environment = launch.call_args.args[2]
        self.assertEqual(environment["KALINKA_DISPLAY_BACKLIGHT"], str(control))
        control.write_text("4")
        self.module["restore_display"]()
        self.assertEqual(control.read_text(), "0")

    def test_prefers_firmware_backlight(self):
        self.panel("raw", "raw")
        preferred = self.panel("firmware", "firmware")
        with patch.object(self.module["os"], "chown"):
            self.module["_prepare_backlight"]()
        self.assertEqual(self.module["_backlight_state"]()[0], preferred)

    def test_no_backlight_still_launches_without_a_power_path(self):
        self.state["_overrides"] = lambda: {"base_config.display.enabled": True}
        self.module["prepare"]()
        with patch.object(self.module["os"], "execve") as launch:
            self.module["run"]()
        self.assertNotIn("KALINKA_DISPLAY_BACKLIGHT", launch.call_args.args[2])

    def test_unwritable_backlight_falls_back(self):
        self.panel()
        with patch.object(self.module["os"], "chown", side_effect=PermissionError):
            self.module["_prepare_backlight"]()
        self.assertIsNone(self.module["_backlight_state"]())

    def test_restore_never_follows_a_path_from_the_runtime_manifest(self):
        target = self.root / "unrelated"
        target.write_text("leave alone")
        (self.root / "backlight.json").write_text(json.dumps({
            "device": str(target), "power": 0,
        }))
        self.module["restore_display"]()
        self.assertEqual(target.read_text(), "leave alone")

    def test_disabled_display_does_not_touch_panel_power(self):
        control = self.panel()
        self.state["_overrides"] = lambda: {"base_config.display.enabled": False}
        with self.assertRaises(SystemExit) as stopped:
            self.module["prepare"]()
        self.assertEqual(stopped.exception.code, 1)
        self.assertEqual(control.read_text(), "0")
        self.assertFalse((self.root / "backlight.json").exists())


if __name__ == "__main__":
    unittest.main()
