import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("macos_dmg", ROOT / "Scripts/package-macos-dmg.py")
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)


class MacOSDiskImageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.app = self.directory / "Inbox+.app"
        contents = self.app / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.inboxplus.installer-fixture",
            "CFBundleExecutable": "fixture",
            "CFBundleName": "Inbox+",
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "AppIcon.icns",
        }))
        self.output = self.directory / "InboxPlus-fixture.dmg"

    def test_existing_image_is_never_replaced(self):
        self.output.write_bytes(b"published image")
        with self.assertRaisesRegex(ValueError, "already exists"):
            dmg.create(self.app, self.output)
        self.assertEqual(self.output.read_bytes(), b"published image")

    def test_non_bundle_is_rejected_before_running_tools(self):
        with patch.object(dmg.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "application bundle"):
                dmg.create(self.directory, self.output)
            run.assert_not_called()

    def test_busy_volume_is_retried_without_forcing_a_successful_detach(self):
        with patch.object(dmg.subprocess, "run", side_effect=[
            subprocess.CompletedProcess([], 1), subprocess.CompletedProcess([], 0),
        ]) as run, patch.object(dmg.time, "sleep") as sleep:
            dmg.detach("/dev/fixture")
        self.assertEqual([call.args[0] for call in run.call_args_list], [
            ["hdiutil", "detach", "/dev/fixture"], ["hdiutil", "detach", "/dev/fixture"],
        ])
        sleep.assert_called_once_with(2)

    def test_persistently_busy_volume_is_forced_only_after_bounded_retries(self):
        with patch.object(dmg.subprocess, "run", side_effect=[
            *[subprocess.CompletedProcess([], 1) for _ in range(5)],
            subprocess.CompletedProcess([], 0),
        ]) as run, patch.object(dmg.time, "sleep") as sleep:
            dmg.detach("/dev/fixture")
        self.assertEqual(run.call_count, 6)
        self.assertEqual(run.call_args.args[0], ["hdiutil", "detach", "-force", "/dev/fixture"])
        self.assertEqual(sleep.call_count, 4)

    def test_cleanup_failure_does_not_replace_the_layout_error(self):
        layout_error = subprocess.CalledProcessError(1, ["osascript"])
        cleanup_error = subprocess.CalledProcessError(1, ["hdiutil", "detach", "-force"])

        def run(command, **kwargs):
            if command[0] == "osascript":
                raise layout_error
            return subprocess.CompletedProcess(command, 0, stdout=plistlib.dumps({
                "system-entities": [{"dev-entry": "/dev/fixture", "mount-point": "/fixture"}],
            }))

        with patch.object(dmg.subprocess, "run", side_effect=run), \
                patch.object(dmg, "detach", side_effect=cleanup_error):
            with self.assertRaises(subprocess.CalledProcessError) as raised:
                dmg.create(self.app, self.output)
        self.assertIs(raised.exception, layout_error)
        self.assertIn("cleanup also failed", layout_error.__notes__[0])
        self.assertFalse(self.output.exists())

    def test_layout_failure_detaches_the_owned_volume_without_creating_an_image(self):
        calls = []

        def run(command, **kwargs):
            calls.append(command)
            if command[0] == "osascript":
                raise subprocess.CalledProcessError(1, command)
            return subprocess.CompletedProcess(command, 0, stdout=plistlib.dumps({
                "system-entities": [{"dev-entry": "/dev/fixture", "mount-point": "/fixture"}],
            }))

        with patch.object(dmg.subprocess, "run", side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError):
                dmg.create(self.app, self.output)
        self.assertEqual(calls[-1], ["hdiutil", "detach", "/dev/fixture"])
        self.assertFalse(self.output.exists())

    @unittest.skipUnless(sys.platform == "darwin" and os.environ.get("INBOXPLUS_TEST_DMG") == "1",
                         "requires an opted-in macOS desktop with Finder automation")
    def test_real_image_keeps_bundle_signature_links_permissions_and_layout(self):
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir()
        shutil.copy("/usr/bin/true", contents / "MacOS/fixture")
        (contents / "Resources").mkdir()
        shutil.copy2(ROOT / "Resources/AppIcon.icns", contents / "Resources/AppIcon.icns")
        framework = contents / "Frameworks/Fixture.framework/Versions"
        (framework / "A").mkdir(parents=True)
        (framework / "Current").symlink_to("A")
        (framework / "A/Resources").mkdir()
        (framework / "A/Resources/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.inboxplus.installer-fixture.framework",
            "CFBundleExecutable": "Fixture", "CFBundlePackageType": "FMWK",
        }))
        (framework.parent / "Fixture").symlink_to("Versions/Current/Fixture")
        (framework.parent / "Resources").symlink_to("Versions/Current/Resources")
        subprocess.run(["clang", "-dynamiclib", "-x", "c", "-", "-o", str(framework / "A/Fixture")],
                       input="int fixture(void) { return 0; }", text=True, check=True, timeout=120)
        subprocess.run(["codesign", "--sign", "-", str(framework.parent)], check=True, timeout=120)
        subprocess.run(["codesign", "--force", "--sign", "-", str(self.app)], check=True, timeout=120)
        signature = (contents / "_CodeSignature/CodeResources").read_bytes()
        dmg.create(self.app, self.output)
        attached = subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist",
                                   str(self.output)], capture_output=True, check=True, timeout=120)
        mount = Path(next(entity["mount-point"] for entity in
                         plistlib.loads(attached.stdout)["system-entities"] if "mount-point" in entity))
        try:
            self.assertEqual(os.readlink(mount / "Applications"), "/Applications")
            self.assertEqual(os.readlink(mount / "Inbox+.app/Contents/Frameworks/Fixture.framework/Versions/Current"), "A")
            self.assertTrue(os.access(mount / "Inbox+.app/Contents/MacOS/fixture", os.X_OK))
            self.assertEqual((mount / "Inbox+.app/Contents/_CodeSignature/CodeResources").read_bytes(), signature)
            self.assertTrue((mount / ".DS_Store").stat().st_size > 0)
            dimensions = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "dpiWidth",
                                         str(mount / ".background/installer.png")],
                                        capture_output=True, text=True, check=True, timeout=30).stdout
            self.assertIn("pixelWidth: 1400", dimensions)
            self.assertIn("pixelHeight: 800", dimensions)
            self.assertIn("dpiWidth: 144", dimensions)
            subprocess.run(["codesign", "--verify", "--strict", str(mount / "Inbox+.app")],
                           check=True, timeout=120)
            installed = self.directory / "installed/Inbox+.app"
            subprocess.run(["ditto", str(mount / "Inbox+.app"), str(installed)], check=True, timeout=120)
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(installed)], check=True, timeout=120)
            layout = subprocess.run(["osascript", "-", str(mount)], text=True, capture_output=True,
                                    check=True, timeout=120, input='''
on run arguments
    tell application "Finder"
        set installer to folder ((POSIX file (item 1 of arguments)) as alias)
        open installer
        set geometry to {icon size of icon view options of container window of installer, ¬
            position of item "Inbox+.app" of installer, position of item "Applications" of installer}
        close container window of installer
        return geometry
    end tell
end run
''')
            self.assertEqual(layout.stdout.strip(), "112, 210, 228, 490, 228")
        finally:
            dmg.detach(str(mount))


if __name__ == "__main__":
    unittest.main()
