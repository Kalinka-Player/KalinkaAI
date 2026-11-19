"""Exercise display and HDMI-CEC setup without touching real hardware."""
import errno
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
        self.drm = self.root / "drm"
        self.drm.mkdir()
        self.module = runpy.run_path(
            str(Path(__file__).resolve().parents[1] / "packaging/kiosk/kalinka-kiosk-ctl")
        )
        self.state = self.module["prepare"].__globals__
        self.state["RUN_DIR"] = str(self.root)
        self.state["BACKLIGHT_DIR"] = self.backlights
        self.state["DRM_DIR"] = self.drm

    def connector(self, name, size_cm=None, status="connected"):
        connector = self.drm / name
        connector.mkdir()
        (connector / "status").write_text(status + "\n")
        if size_cm is not None:
            edid = bytearray(128)
            edid[:8] = bytes.fromhex("00 ff ff ff ff ff ff 00")
            edid[21:23] = bytes(size_cm)
            edid[-1] = -sum(edid) % 256
            (connector / "edid").write_bytes(edid)
        return connector

    def test_reports_tv_size_without_overriding_flutter_display_metrics(self):
        self.connector("card1-HDMI-A-1", (121, 68))
        self.connector("card1-HDMI-A-2", status="disconnected")
        self.state["_overrides"] = lambda: {
            "base_config.display.enabled": True, "base_config.display.rotation": "90",
        }
        self.module["prepare"]()
        with patch.dict(self.module["os"].environ, {"KALINKA_KIOSK_VIDEOMODE": ""}), \
                patch.object(self.module["os"], "execve") as launch:
            self.module["run"]()
        binary, args, env = launch.call_args.args
        self.assertEqual(args, [binary, "--release", "--rotation", "90", self.state["BUNDLE"]])
        self.assertAlmostEqual(float(env["KALINKA_DISPLAY_DIAGONAL_INCHES"]), 54.64, delta=0.1)

    def test_explicit_video_mode_is_passed_with_the_configured_rotation(self):
        self.state["_overrides"] = lambda: {
            "base_config.display.enabled": True, "base_config.display.rotation": "90",
        }
        self.module["prepare"]()
        with patch.dict(self.module["os"].environ, {"KALINKA_KIOSK_VIDEOMODE": "1920x1080@60"}), \
                patch.object(self.module["os"], "execve") as launch:
            self.module["run"]()
        binary, args, _ = launch.call_args.args
        self.assertEqual(args, [binary, "--release", "--rotation", "90",
                                "--videomode", "1920x1080@60", self.state["BUNDLE"]])

    def test_missing_invalid_or_ambiguous_edid_uses_flutter_density(self):
        panel = self.connector("card1-DSI-1")
        diagonal = self.module["_display_diagonal_inches"]
        self.assertIsNone(diagonal())
        tv = self.connector("card1-HDMI-A-1", (121, 68))
        self.assertIsNone(diagonal())
        (panel / "status").write_text("disconnected\n")
        edid = tv / "edid"
        data = bytearray(edid.read_bytes())
        data[22] = 0
        data[-1] = -sum(data[:-1]) % 256
        edid.write_bytes(data)
        self.assertIsNone(diagonal())
        data[22] = 68  # The dimensions now disagree with the checksum.
        edid.write_bytes(data)
        self.assertIsNone(diagonal())

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


class KioskCecTest(unittest.TestCase):
    def setUp(self):
        module = runpy.run_path(str(Path(__file__).resolve().parents[1]
                                    / "packaging/kiosk/kalinka-kiosk-cec"))
        self.configure = module["configure"]
        self.source = module["PlaybackSource"]()
        self.source.set_address(0x3000, 1 << 8)
        self.first_connected_display = module["first_connected_display"]
        self.address = module["LogicalAddresses"]()
        self.driver = b"vc4_hdmi"
        self.caps = module["PLAYBACK_CAPS"] | module["CONNECTOR_INFO_CAP"]
        self.mode_error = None
        self.writes = []
        self.busy_once = False
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.marker = Path(directory.name) / "cec0"

        def ioctl(fd, request, value):
            if request == module["GET_CAPS"]:
                value.driver = self.driver
                value.capabilities = self.caps
            elif request == module["GET_CONNECTOR"]:
                value[0], value[1], value[2] = 1, 1, 52
            elif request == module["GET_ADDRESSES"]:
                module["c"].memmove(module["c"].addressof(value),
                                    module["c"].addressof(self.address),
                                    module["c"].sizeof(value))
            elif request == module["SET_MODE"]:
                self.assertEqual(value.value, module["INITIATOR_AND_FOLLOWER"])
                if self.mode_error is not None:
                    raise self.mode_error
            elif request == module["SET_ADDRESSES"]:
                if self.busy_once:
                    self.busy_once = False
                    raise OSError(errno.EBUSY, "CEC adapter busy")
                self.address = value
                self.writes.append(value.num_log_addrs)
            else:
                self.fail(f"Unexpected ioctl {request}")

        self.enterContext(patch.object(module["fcntl"], "ioctl", side_effect=ioctl))

    def test_responds_to_tv_selection_until_route_standby_or_address_changes(self):
        request = bytes.fromhex("0f 85")
        selected = bytes.fromhex("0f 86 30 00")
        active = bytes.fromhex("8f 82 30 00")
        self.assertIsNone(self.source.reply(request))
        for other in ("4f 82 10 00", "0f 86 10 00", "0f 80 30 00 10 00", "0f 36"):
            self.assertEqual(self.source.reply(selected), active)
            self.assertEqual(self.source.reply(request), active)
            self.assertIsNone(self.source.reply(bytes.fromhex(other)))
            self.assertIsNone(self.source.reply(request))
        self.assertEqual(self.source.reply(selected), active)
        self.source.set_address(0xffff, 0)
        self.assertIsNone(self.source.reply(selected))
        self.source.set_address(0x2000, 1 << 4)
        self.assertIsNone(self.source.reply(request))
        self.assertEqual(self.source.reply(bytes.fromhex("0f 86 20 00")),
                         bytes.fromhex("4f 82 20 00"))

    def test_answers_power_and_samsung_discovery_but_leaves_keys_to_linux(self):
        for query, reply in (("08 8f", "80 90 00"),
                             ("08 a0 00 00 f0 23", "80 a0 00 00 f0 24 00 80"),
                             ("08 a0 01 02 03 23", "80 00 a0 00")):
            self.assertEqual(self.source.reply(bytes.fromhex(query)), bytes.fromhex(reply))
        for frame in ("08 44 01", "08 45", "04 8f", "0f 8f", "08 00 8f 00"):
            self.assertIsNone(self.source.reply(bytes.fromhex(frame)))

    def test_configures_unplugged_adapter_once_and_releases_on_stop(self):
        self.configure(4, self.marker, release=False)
        self.assertEqual(self.address.osd_name, b"Kalinka")
        self.assertEqual(self.address.log_addr_type[0], 3)
        self.assertEqual(self.address.flags, 2)
        self.configure(4, self.marker, release=False)
        self.configure(4, self.marker, release=True)
        self.configure(4, self.marker, release=True)
        self.assertEqual(self.writes, [1, 0])

    def test_foreign_owner_and_unsupported_adapters_are_untouched(self):
        self.address.num_log_addrs = 1
        self.configure(4, self.marker, release=False)
        self.configure(4, self.marker, release=True)
        self.address.num_log_addrs = 0
        self.driver = b"other"
        self.configure(4, self.marker, release=False)
        self.driver = b"vc4_hdmi"
        self.caps = 2  # No input passthrough.
        self.configure(4, self.marker, release=False)
        self.assertEqual(self.writes, [])

    def test_replacement_role_is_preserved_on_stop(self):
        self.configure(4, self.marker, release=False)
        self.address.osd_name = b"Amplifier"
        self.configure(4, self.marker, release=True)
        self.assertEqual(self.writes, [1])

    def test_busy_setup_does_not_record_ownership_and_busy_release_retries(self):
        self.busy_once = True
        with self.assertRaises(OSError):
            self.configure(4, self.marker, release=False)
        self.assertFalse(self.marker.exists())
        self.configure(4, self.marker, release=False)
        self.busy_once = True
        self.configure(4, self.marker, release=True)
        self.assertEqual(self.writes, [1, 0])
        self.assertFalse(self.marker.exists())

    def test_cannot_claim_a_role_without_follower_mode(self):
        self.mode_error = OSError(errno.EBUSY, "Follower unavailable")
        with self.assertRaises(OSError):
            self.configure(4, self.marker, release=False)
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.writes, [])

    def test_an_unregistered_address_cannot_announce_or_answer(self):
        self.source.set_address(0x3000, 1 << 15)
        self.assertIsNone(self.source.reply(bytes.fromhex("0f 86 30 00")))

    def test_registers_only_the_port_serving_the_display(self):
        drm = self.marker.parent
        for name, status, connector in [("HDMI-A-1", "disconnected", 42),
                                        ("HDMI-A-2", "connected", 52),
                                        ("DSI-1", "connected", 75)]:
            port = drm / f"card1-{name}"
            port.mkdir()
            (port / "status").write_text(status)
            (port / "connector_id").write_text(str(connector))
        self.assertEqual(self.first_connected_display(drm), (1, 52))
        self.configure(4, self.marker, release=False, display=(1, 75))
        self.assertEqual(self.writes, [])
        self.configure(4, self.marker, release=False, display=(1, 52))
        self.assertEqual(self.writes, [1])


if __name__ == "__main__":
    unittest.main()
