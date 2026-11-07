import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile


root = Path(__file__).resolve().parents[2]
specification = importlib.util.spec_from_file_location(
    "flutter_desktop", root / "Scripts/package-flutter-desktop.py")
packaging = importlib.util.module_from_spec(specification)
specification.loader.exec_module(packaging)


def elf(machine=62):
    header = bytearray(64)
    header[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", header, 18, machine)
    return bytes(header)


def pe(machine=0x8664):
    header = bytearray(128)
    header[:2] = b"MZ"
    struct.pack_into("<I", header, 60, 64)
    header[64:68] = b"PE\0\0"
    struct.pack_into("<H", header, 68, machine)
    return bytes(header)


class FlutterDesktopPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.location = Path(self.temporary.name)

    def bundle(self, target):
        bundle = self.location / ("Inbox+v2.app" if target == "macos" else "bundle")
        if target == "linux":
            files = {"InboxPlus": elf(), "lib/libinboxplus_connectors.so": elf(),
                     "lib/libflutter_linux_gtk.so": elf(), "lib/libapp.so": elf(),
                     "lib/libsqlite3mc.so": elf()}
            assets = "data/flutter_assets"
        elif target == "windows":
            files = {"InboxPlus.exe": pe(), "inboxplus_connectors.dll": pe(),
                     "flutter_windows.dll": pe(), "data/app.so": elf(), "sqlite3mc.dll": pe()}
            assets = "data/flutter_assets"
        else:
            files = {"Contents/MacOS/Inbox+v2": b"\xcf\xfa\xed\xfe",
                     "Contents/Frameworks/libinboxplus_connectors.dylib": b"\xcf\xfa\xed\xfe",
                     "Contents/Frameworks/App.framework/App": b"\xcf\xfa\xed\xfe",
                     "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS": b"\xcf\xfa\xed\xfe"}
            assets = "Contents/Frameworks/App.framework/Resources/flutter_assets"
        for name, data in files.items():
            file = bundle / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            file.chmod(0o755)
        if target == "macos":
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.inboxplus.app",
                "CFBundleExecutable": "Inbox+v2",
                "CFBundleShortVersionString": "0.9.0",
                "CFBundleVersion": "112",
            }))
        for name in ("third_party_notices.txt", "reaction_emoji.json", "inboxplus-logo.png"):
            file = bundle / assets / "assets" / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes((root / "apps/inboxplus_flutter/assets" / name).read_bytes())
        (bundle / assets / "AssetManifest.bin").write_bytes(b"fixture assets")
        if target != "macos":
            (bundle / assets / "NativeAssetsManifest.json").write_text(json.dumps({
                "format-version": [1, 0, 0], "native-assets": {target + "_x64": {
                    "package:sqlite3/src/ffi/libsqlite3.g.dart": ["absolute", "sqlite3mc.dll" if target == "windows" else "libsqlite3mc.so"]}}}))
        return bundle

    @unittest.skipIf(os.name == "nt", "POSIX executable modes and links require a POSIX host")
    def test_linux_archive_keeps_runtime_permissions_and_internal_symlinks(self):
        bundle = self.bundle("linux")
        (bundle / "lib/alias.so").symlink_to("libapp.so")
        result = packaging.package("linux", bundle, self.location / "out")
        with tarfile.open(result) as archive:
            executable = archive.getmember("Inbox+v2/InboxPlus")
            self.assertEqual(executable.mode & 0o111, 0o111)
            self.assertEqual(archive.extractfile(executable).read(), elf())
            link = archive.getmember("Inbox+v2/lib/alias.so")
            self.assertTrue(link.issym())
            self.assertEqual(link.linkname, "libapp.so")
            metadata = json.load(archive.extractfile("Inbox+v2/build-info.json"))
            self.assertEqual(metadata["architectures"], ["x64"])
            self.assertTrue(metadata["development"])
            self.assertIn("Inbox+v2/LICENSE", archive.getnames())
            self.assertIn("Inbox+v2/sbom.cdx.json", archive.getnames())
        checksum = Path(str(result) + ".sha256").read_text()
        self.assertEqual(checksum, hashlib.sha256(result.read_bytes()).hexdigest() + "  " + result.name + "\n")

    def test_windows_zip_includes_dlls_assets_and_account_independent_metadata(self):
        bundle = self.bundle("windows")
        result = packaging.package("windows", bundle, self.location / "out")
        with zipfile.ZipFile(result) as archive:
            self.assertEqual(archive.read("Inbox+v2/inboxplus_connectors.dll"), pe())
            self.assertEqual(archive.read("Inbox+v2/flutter_windows.dll"), pe())
            self.assertEqual(archive.read("Inbox+v2/data/app.so"), elf())
            self.assertIn("Inbox+v2/data/flutter_assets/assets/third_party_notices.txt", archive.namelist())
            metadata = json.loads(archive.read("Inbox+v2/build-info.json"))
            self.assertEqual(metadata["entrypoint"], "InboxPlus.exe")
            self.assertNotIn(str(self.location), json.dumps(metadata))

    def test_windows_rejects_mismatched_snapshot_architecture_and_elf_dlls(self):
        bundle = self.bundle("windows")
        snapshot = bundle / "data/app.so"
        snapshot.write_bytes(elf(183))
        with self.assertRaisesRegex(RuntimeError, "architecture"):
            packaging.package("windows", bundle, self.location / "out")
        snapshot.write_bytes(elf())
        (bundle / "inboxplus_connectors.dll").write_bytes(elf())
        with self.assertRaisesRegex(RuntimeError, "Unsupported binary architecture"):
            packaging.package("windows", bundle, self.location / "out")

    def test_native_asset_paths_must_remain_inside_the_bundle_on_every_host(self):
        bundle = self.bundle("windows")
        manifest_file = bundle / "data/flutter_assets/NativeAssetsManifest.json"
        manifest = json.loads(manifest_file.read_text())
        for path in ("/sqlite3mc.dll", "../sqlite3mc.dll", "C:/sqlite3mc.dll",
                     "C:sqlite3mc.dll", "\\\\server\\sqlite3mc.dll"):
            with self.subTest(path=path):
                manifest["native-assets"]["windows_x64"]["package:sqlite3/src/ffi/libsqlite3.g.dart"] = ["absolute", path]
                manifest_file.write_text(json.dumps(manifest))
                with self.assertRaisesRegex(RuntimeError, "Native asset is not relocatable"):
                    packaging.package("windows", bundle, self.location / "out")

    def test_missing_connector_and_debug_assets_fail_before_creating_an_archive(self):
        bundle = self.bundle("windows")
        connector = bundle / "inboxplus_connectors.dll"
        connector.unlink()
        output = self.location / "out"
        with self.assertRaisesRegex(RuntimeError, "Missing runtime file"):
            packaging.package("windows", bundle, output)
        self.assertFalse(output.exists())
        connector.write_bytes(pe())
        (bundle / "data/flutter_assets/kernel_blob.bin").write_bytes(b"debug fixture")
        with self.assertRaisesRegex(RuntimeError, "Debug"):
            packaging.package("windows", bundle, output)

    def test_mismatched_binary_architectures_and_stale_notices_are_rejected(self):
        bundle = self.bundle("windows")
        (bundle / "inboxplus_connectors.dll").write_bytes(pe(0xaa64))
        with self.assertRaisesRegex(RuntimeError, "architecture"):
            packaging.package("windows", bundle, self.location / "out")
        (bundle / "inboxplus_connectors.dll").write_bytes(pe())
        (bundle / "data/flutter_assets/assets/third_party_notices.txt").write_text("stale")
        with self.assertRaisesRegex(RuntimeError, "Bundled asset"):
            packaging.package("windows", bundle, self.location / "out")

    @unittest.skipIf(os.name == "nt", "Linux executable modes require a POSIX host")
    def test_corrupted_required_and_native_asset_libraries_are_rejected(self):
        bundle = self.bundle("linux")
        output = self.location / "out"
        for name in ("lib/libinboxplus_connectors.so", "lib/libsqlite3mc.so"):
            with self.subTest(library=name):
                library = bundle / name
                library.write_bytes(b"corrupted runtime")
                with self.assertRaisesRegex(RuntimeError, "Unsupported binary architecture"):
                    packaging.package("linux", bundle, output)
                self.assertFalse(output.exists())
                library.write_bytes(elf())

    @unittest.skipIf(os.name == "nt", "Symlink creation requires privileges on Windows")
    def test_external_links_and_output_inside_the_bundle_are_rejected(self):
        bundle = self.bundle("linux")
        outside = self.location / "private.txt"
        outside.write_text("outside profile fixture")
        link = bundle / "lib/external.so"
        link.symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError, "outside"):
            packaging.package("linux", bundle, self.location / "out")
        link.unlink()
        with self.assertRaisesRegex(RuntimeError, "inside"):
            packaging.package("linux", bundle, bundle / "out")

    def test_macos_rejects_comparison_identity_and_mismatched_version(self):
        bundle = self.bundle("macos")
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        info["CFBundleIdentifier"] = "com.inboxplus.desktop-comparison"
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(RuntimeError, "identity"):
            packaging.package("macos", bundle, self.location / "out")
        info.update(CFBundleIdentifier="com.inboxplus.app", CFBundleVersion="111")
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(RuntimeError, "version"):
            packaging.package("macos", bundle, self.location / "out")

    def test_failed_archive_preserves_a_previous_package_and_cleans_staging(self):
        bundle = self.bundle("windows")
        output = self.location / "out"
        original = packaging.package("windows", bundle, output)
        before = original.read_bytes()
        with patch.object(packaging, "write_archive", side_effect=RuntimeError("fixture write failure")):
            with self.assertRaisesRegex(RuntimeError, "fixture write failure"):
                packaging.package("windows", bundle, output)
        self.assertEqual(original.read_bytes(), before)
        self.assertFalse(any(path.name.startswith(".inboxplus-package-") for path in output.iterdir()))


if __name__ == "__main__":
    unittest.main()
