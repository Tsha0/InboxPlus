from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class MacOSIconTests(unittest.TestCase):
    def test_flutter_runner_declares_an_existing_icon(self):
        with (ROOT / "apps/inboxplus_flutter/macos/Runner/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        self.assertTrue((ROOT / "Resources" / info["CFBundleIconFile"]).is_file())

    @unittest.skipUnless(sys.platform == "darwin", "iconutil requires macOS")
    def test_app_icon_contains_every_macos_size(self):
        with tempfile.TemporaryDirectory() as directory:
            extracted = Path(directory) / "AppIcon.iconset"
            subprocess.run(
                ["/usr/bin/iconutil", "-c", "iconset", str(ROOT / "Resources/AppIcon.icns"), "-o", str(extracted)],
                check=True, capture_output=True, timeout=60,
            )
            expected = {
                "icon_16x16.png", "icon_16x16@2x.png", "icon_32x32.png", "icon_32x32@2x.png",
                "icon_128x128.png", "icon_128x128@2x.png", "icon_256x256.png", "icon_256x256@2x.png",
                "icon_512x512.png", "icon_512x512@2x.png",
            }
            self.assertTrue(expected.issubset(path.name for path in extracted.iterdir()))


if __name__ == "__main__":
    unittest.main()
