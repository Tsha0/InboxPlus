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
feed_finalization = load("finalize-update-feed")


class UpdatePackagingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "Inbox+.app"
        self.plist = self.app / "Contents/Info.plist"
        self.plist.parent.mkdir(parents=True)
        self.plist.write_bytes(plistlib.dumps({"CFBundleVersion": "106"}))
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

    def test_delta_updates_ship_signed_with_their_release_under_safe_names(self):
        root, _, path = self.feed()
        deltas = ET.SubElement(root.find("./channel/item"), f"{{{feed_validation.SPARKLE}}}deltas")
        delta = ET.SubElement(deltas, "enclosure", {
            "url": "https://github.com/Tsha0/InboxPlus/releases/download/v0.6.0/InboxPlus-106-105.delta",
            "length": "678",
            f"{{{feed_validation.SPARKLE}}}deltaFrom": "105",
            f"{{{feed_validation.SPARKLE}}}edSignature": base64.b64encode(bytes(64)).decode(),
        })
        ET.ElementTree(root).write(path)
        feed_validation.validate(path, "Tsha0/InboxPlus", "v0.6.0", "106")
        valid = dict(delta.attrib)
        for name, value in [
            ("url", "https://github.com/Tsha0/InboxPlus/releases/download/v0.6.0/Inbox+106-105.delta"),
            ("url", "https://github.com/Tsha0/InboxPlus/releases/download/v0.5.0/InboxPlus-106-105.delta"),
            ("url", "https://github.com/Tsha0/InboxPlus/releases/download/v0.6.0/InboxPlus-106-105.zip"),
            (f"{{{feed_validation.SPARKLE}}}deltaFrom", "106"),
            (f"{{{feed_validation.SPARKLE}}}edSignature", ""),
            ("length", "0"),
        ]:
            delta.attrib = {**valid, name: value}
            ET.ElementTree(root).write(path)
            with self.subTest(**{name.rsplit("}", 1)[-1]: value}), self.assertRaises(ValueError):
                feed_validation.validate(path, "Tsha0/InboxPlus", "v0.6.0", "106")


    def test_finalization_preserves_published_entries_pruned_by_sparkle(self):
        stage = Path(self.directory.name)
        previous_items = [
            f'<item><sparkle:version>{build}</sparkle:version><description>Original {build}</description></item>'
            for build in [109, 108, 107]
        ]
        current = '<item><sparkle:version>111</sparkle:version></item>'
        rewritten = '<item><sparkle:version>109</sparkle:version><description>Changed</description></item>'
        feed = stage / "appcast.xml"
        feed.write_text('<rss><channel>' + current + rewritten + '</channel></rss>')
        feed_finalization.finalize(stage, ''.join(previous_items), "111", "https://example.com/")
        result = feed.read_text()
        self.assertIn(current, result)
        for item in previous_items:
            self.assertEqual(result.count(item), 1)
        self.assertNotIn("Changed", result)


class MacOSReleaseTests(unittest.TestCase):
    def setUp(self):
        self.packaging = load("package-macos-release")
        self.environment = {
            "INBOXPLUS_RELEASE_SIGNING": "self-signed",
            "INBOXPLUS_SIGNING_IDENTITY": "Fixture release certificate",
        }

    def test_release_keeps_existing_updater_trust_and_rejects_ad_hoc_signing(self):
        from unittest.mock import patch
        with patch.object(self.packaging.desktop, "version", return_value=("0.9.0", "114")):
            self.assertEqual(self.packaging.release_settings(self.environment, None)[:3], ("0.9.0", "114", "v0.9.0"))
            for field, value in [
                ("INBOXPLUS_RELEASE_TAG", "v0.8.5"),
                ("INBOXPLUS_SIGNING_IDENTITY", "-"),
                ("INBOXPLUS_SIGNING_IDENTITY", ""),
                ("INBOXPLUS_UPDATE_PUBLIC_KEY", base64.b64encode(bytes(32)).decode()),
                ("INBOXPLUS_UPDATE_FEED_URL", "https://example.com/new-feed.xml"),
                ("INBOXPLUS_RELEASE_SIGNING", "ad-hoc"),
                ("INBOXPLUS_RELEASE_SIGNING", "developer-id"),
            ]:
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    self.packaging.release_settings({**self.environment, field: value}, None)

    def test_release_build_must_exceed_all_published_versions(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            previous = Path(directory) / "previous.xml"
            previous.write_text(f'<rss xmlns:sparkle="{feed_validation.SPARKLE}"><channel><item>'
                                '<sparkle:version>115</sparkle:version></item></channel></rss>')
            with patch.object(self.packaging.desktop, "version", return_value=("0.9.0", "114")):
                with self.assertRaisesRegex(ValueError, "every previously published"):
                    self.packaging.release_settings(self.environment, previous)
            with patch.object(self.packaging.desktop, "version", return_value=("0.9.0", "111")):
                with self.assertRaisesRegex(ValueError, "shipped 0.8.5"):
                    self.packaging.release_settings(self.environment, None)

    def test_reconfiguring_development_build_removes_stale_production_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Inbox+.app"
            plist = app / "Contents/Info.plist"
            plist.parent.mkdir(parents=True)
            plist.write_bytes(plistlib.dumps({"SUFeedURL": "https://example.com/feed", "SUAutomaticallyUpdate": True}))
            configuration.configure(app, False, {})
            info = plistlib.loads(plist.read_bytes())
            self.assertFalse(info["InboxPlusUpdatesEnabled"])
            self.assertNotIn("SUFeedURL", info)
            self.assertNotIn("SUAutomaticallyUpdate", info)

    def test_feed_publication_rejects_rollback_and_changed_previous_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            current, previous = (Path(directory) / name for name in ("current.xml", "previous.xml"))
            def document(builds):
                return f'<rss xmlns:sparkle="{feed_validation.SPARKLE}"><channel>' + ''.join(
                    f'<item><sparkle:version>{build}</sparkle:version><description>Original</description></item>'
                    for build in builds) + '</channel></rss>'
            previous.write_text(document([111, 109]))
            current.write_text(document([114, 111, 109]))
            feed_validation.validate_publication(current, previous)
            feed_validation.validate_publication(previous, previous)
            current.write_text(document([109]))
            with self.assertRaisesRegex(ValueError, "roll back"):
                feed_validation.validate_publication(current, previous)
            current.write_text(document([114, 111]))
            with self.assertRaisesRegex(ValueError, "unchanged"):
                feed_validation.validate_publication(current, previous)
            current.write_text(document([114, 111, 109]).replace('Original', 'Changed'))
            with self.assertRaisesRegex(ValueError, "unchanged"):
                feed_validation.validate_publication(current, previous)

    def test_flutter_build_number_is_not_overridden_by_release_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Inbox+.app"
            plist = app / "Contents/Info.plist"
            plist.parent.mkdir(parents=True)
            original = plistlib.dumps({"CFBundleVersion": "114"})
            plist.write_bytes(original)
            with self.assertRaisesRegex(ValueError, "Flutter build number"):
                configuration.configure(app, True, {
                    "INBOXPLUS_UPDATE_PUBLIC_KEY": base64.b64encode(bytes(32)).decode(),
                    "INBOXPLUS_BUILD_NUMBER": "115",
                })
            self.assertEqual(plist.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
