import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


configuration = load("configure-updates")
feed_validation = load("validate-update-feed")


class UpdatePackagingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "Inbox+.app"
        self.plist = self.app / "Contents/Info.plist"
        self.plist.parent.mkdir(parents=True)
        self.plist.write_bytes(plistlib.dumps({"CFBundleVersion": "0.5.0"}))
        self.environment = {
            "INBOXPLUS_UPDATE_PUBLIC_KEY": base64.b64encode(bytes(range(32))).decode(),
            "INBOXPLUS_BUILD_NUMBER": "106",
        }

    def test_development_bundle_has_no_feed_or_automatic_updates(self):
        configuration.configure(self.app, False, {})
        info = plistlib.loads(self.plist.read_bytes())
        self.assertFalse(info["InboxPlusUpdatesEnabled"])
        self.assertNotIn("SUFeedURL", info)

    def test_release_requires_signing_configuration_before_mutating_plist(self):
        original = self.plist.read_bytes()
        with self.assertRaises(ValueError):
            configuration.configure(self.app, True, {})
        self.assertEqual(original, self.plist.read_bytes())

    def test_release_uses_public_key_build_number_and_https_feed(self):
        configuration.configure(self.app, True, self.environment)
        info = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(info["CFBundleVersion"], "106")
        self.assertEqual(info["SUPublicEDKey"], self.environment["INBOXPLUS_UPDATE_PUBLIC_KEY"])
        self.assertTrue(info["SUAutomaticallyUpdate"])
        self.assertTrue(info["SUEnableAutomaticChecks"])
        self.assertFalse(info["SUEnableSystemProfiling"])

    def test_insecure_or_credentialed_feed_is_rejected(self):
        for url in ["http://example.com/feed", "https://user:password@example.com/feed"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                configuration.configure(self.app, True, {**self.environment, "INBOXPLUS_UPDATE_FEED_URL": url})

    def test_invalid_build_numbers_are_rejected(self):
        for build in ["0", "-1", "0.6.0", "١٠٦"]:
            with self.subTest(build=build), self.assertRaises(ValueError):
                configuration.configure(self.app, True, {**self.environment, "INBOXPLUS_BUILD_NUMBER": build})

    def feed(self):
        root = ET.Element("rss")
        item = ET.SubElement(ET.SubElement(root, "channel"), "item")
        enclosure = ET.SubElement(item, "enclosure", {
            "url": "https://github.com/Tsha0/InboxPlus/releases/download/v0.6.0/InboxPlus-0.6.0-106.zip",
            "length": "12345",
            f"{{{feed_validation.SPARKLE}}}version": "106",
            f"{{{feed_validation.SPARKLE}}}edSignature": base64.b64encode(bytes(64)).decode(),
        })
        path = Path(self.directory.name) / "appcast.xml"
        return root, enclosure, path

    def test_feed_requires_this_release_and_signed_archive_metadata(self):
        root, enclosure, path = self.feed()
        ET.ElementTree(root).write(path)
        feed_validation.validate(path, "Tsha0/InboxPlus", "v0.6.0")
        with self.assertRaises(ValueError):
            feed_validation.validate(path, "Tsha0/InboxPlus", "v0.7.0")
        with self.assertRaises(ValueError):
            feed_validation.validate(path, "Tsha0/InboxPlus", "v0.6.0", "107")
        enclosure.set("url", "https://example.com/update.zip")
        ET.ElementTree(root).write(path)
        with self.assertRaises(ValueError):
            feed_validation.validate(path, "Tsha0/InboxPlus", "v0.6.0")


if __name__ == "__main__":
    unittest.main()
