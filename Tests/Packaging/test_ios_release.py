import importlib.util
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


simulator = load_script("select-ios-simulator")
verification = load_script("verify-ios-app")


class SimulatorSelectionTests(unittest.TestCase):
    def runtime(self, version, names, **overrides):
        return {
            "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-"),
            "version": version,
            "isAvailable": True,
            "supportedDeviceTypes": [{"name": name, "identifier": "device-" + name} for name in names],
            **overrides,
        }

    def test_prefers_newest_pro_on_newest_available_ios_runtime(self):
        document = {"runtimes": [
            self.runtime("27.9", ["iPhone 18 Pro"]),
            self.runtime("27.10", ["iPhone 18 Pro Max", "iPhone 17 Pro", "iPhone 18 Pro"]),
            self.runtime("28.0", ["iPhone 19 Pro"], isAvailable=False),
            self.runtime("30.0", ["iPhone 20 Pro"], identifier="com.apple.CoreSimulator.SimRuntime.tvOS-30-0"),
        ]}
        self.assertEqual(simulator.select_runtime_device(document), (
            "com.apple.CoreSimulator.SimRuntime.iOS-27-10", "device-iPhone 18 Pro",
        ))

    def test_uses_supported_iphone_when_no_numbered_pro_exists(self):
        for names in (["iPad Pro", "iPhone Air"], ["iPhone 18 Pro Max"], ["iPhone SE (3rd generation)"]):
            with self.subTest(names=names):
                runtime, device = simulator.select_runtime_device({"runtimes": [self.runtime("27.2", names)]})
                self.assertEqual(runtime, "com.apple.CoreSimulator.SimRuntime.iOS-27-2")
                self.assertEqual(device, "device-" + names[-1])

    def test_missing_runtime_or_iphone_has_a_controlled_error(self):
        for document, message in (
            ({"runtimes": []}, "No available iOS simulator runtime"),
            ({"runtimes": [self.runtime("27.2", ["iPad Pro"])]}, "no supported iPhone"),
        ):
            with self.subTest(document=document), self.assertRaisesRegex(ValueError, message):
                simulator.select_runtime_device(document)


class IOSArtifactVerificationTests(unittest.TestCase):
    def test_real_dyld_info_two_column_format_preserves_connector_symbols(self):
        exports = """Runner [arm64]:
    -exports:
        offset      symbol
        0x00BAA944  _inboxplus_free
        0x00BAA8F4  _inboxplus_poll_event
        0x00BAA894  _inboxplus_request
"""
        self.assertEqual(self.problems(exports), [])

    def test_missing_symbol_is_still_rejected(self):
        problems = self.problems("        0x00BAA944  _inboxplus_free\n")
        self.assertEqual(len(problems), 1)
        self.assertIn("_inboxplus_request", problems[0])
        self.assertIn("_inboxplus_poll_event", problems[0])
        self.assertNotIn("_inboxplus_free", problems[0])

    def problems(self, exports):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Runner.app"
            app.mkdir()
            (app / "PrivacyInfo.xcprivacy").write_text("fixture")
            version, build = verification.app_version()
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
            }))
            with patch.object(verification.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, exports)):
                return verification.problems(app, False)

    def test_export_name_matches_bundle_name_in_both_release_steps(self):
        info = plistlib.loads((ROOT / "apps/inboxplus_flutter/ios/Runner/Info.plist").read_bytes())
        workflow = (ROOT / ".github/workflows/ios-release.yml").read_text()
        filenames = re.findall(r"build/ios/ipa/([^\s]+\.ipa)", workflow)
        self.assertEqual(filenames, [info["CFBundleName"] + ".ipa"] * 2)

    def test_flutter_setup_actions_are_pinned_across_workflows(self):
        for workflow in (ROOT / ".github/workflows").glob("*.yml"):
            for reference in re.findall(r"uses: subosito/flutter-action@(\S+)", workflow.read_text()):
                with self.subTest(workflow=workflow):
                    self.assertRegex(reference, r"^[0-9a-f]{40}$")


if __name__ == "__main__":
    unittest.main()
