import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cache = load("build-connectors-cache")
timing = load("time-macos-build")


class ConnectorBuildCacheTests(unittest.TestCase):
    def test_fingerprint_tracks_source_headers_embedded_data_flags_compiler_and_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {name: root / name for name in ("main.go", "api.h", "data.json", "go.mod", "go.sum", "build.sh")}
            for name, path in files.items():
                path.write_text(name)
            settings = {"CC": "clang", "CXX": "clang", "GOARCH": "arm64", "CGO_CFLAGS": "-mmacosx-version-min=15.0"}
            package = {"Dir": str(root), "GoFiles": ["main.go"], "HFiles": ["api.h"], "EmbedFiles": ["data.json"]}
            compiler, sdk = "clang-1", "sdk-1"

            def output(command, **kwargs):
                if command[1] == "env":
                    return json.dumps(settings)
                if command[1] == "list":
                    return json.dumps(package)
                return compiler if command[0] == "clang" else sdk

            original_digest = cache.digest
            def digest(path):
                return original_digest(files[path.name] if path.name in ("go.mod", "go.sum", "build.sh") else path)

            with patch.object(cache.subprocess, "check_output", side_effect=output), patch.object(cache, "digest", side_effect=digest):
                key, _ = cache.fingerprint("go")
                self.assertEqual(cache.fingerprint("go")[0], key)
                for path in files.values():
                    original = path.read_text()
                    path.write_text(original + "changed")
                    self.assertNotEqual(cache.fingerprint("go")[0], key, path.name)
                    path.write_text(original)
                for option in ("GOARCH", "CGO_CFLAGS"):
                    original = settings[option]
                    settings[option] += "changed"
                    self.assertNotEqual(cache.fingerprint("go")[0], key, option)
                    settings[option] = original
                compiler = "clang-2"
                self.assertNotEqual(cache.fingerprint("go")[0], key)
                compiler, sdk = "clang-1", "sdk-2"
                self.assertNotEqual(cache.fingerprint("go")[0], key)

    def test_reuse_verifies_library_and_header_and_rebuilds_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output.dylib"
            storage = root / "cache"
            def compile(command, **kwargs):
                built = Path(command[command.index("-o") + 1])
                built.write_bytes(b"library")
                built.with_suffix(".h").write_bytes(b"header")

            with patch.object(cache, "fingerprint", return_value=("key", {"GOARCH": "arm64"})), patch.object(cache.subprocess, "run", side_effect=compile) as build:
                cache.build("go", output, storage)
                cache.build("go", output, storage)
                self.assertEqual(build.call_count, 1)
                self.assertEqual(output.read_bytes(), b"library")
                self.assertEqual(output.with_suffix(".h").read_bytes(), b"header")
                for name in ("libinboxplus_connectors.dylib", "libinboxplus_connectors.h"):
                    (storage / "key" / name).write_bytes(b"corrupt")
                    cache.build("go", output, storage)
                self.assertEqual(build.call_count, 3)

    def test_failed_build_never_becomes_a_cache_hit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(cache, "fingerprint", return_value=("key", {"GOARCH": "arm64"})), patch.object(cache.subprocess, "run", side_effect=RuntimeError("compile failed")):
                with self.assertRaises(RuntimeError):
                    cache.build("go", root / "output.dylib", root / "cache")
            self.assertFalse((root / "cache/key/sha256.json").exists())


class MacOSBuildTimingTests(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Fixture command uses a POSIX executable script")
    def test_failed_build_records_timings_without_publishing_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            flutter = root / "flutter"
            flutter.write_text(
                "#!/usr/bin/env python3\n"
                "print('export PRIVATE_VALUE=never-publish')\n"
                "print('Error: Running build hooks failed.')\n"
                "print('Bad state: Hash of downloaded file libsqlite3mc.x64.macos.dylib is rejected')\n"
                "print('Running pod install...')\n"
                "print('executing: xcodebuild -workspace Runner -configuration Release')\n"
                "raise SystemExit(7)\n"
            )
            flutter.chmod(0o755)
            process = subprocess.run(
                [sys.executable, str(ROOT / "Scripts/time-macos-build.py")],
                env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                     "RUNNER_TEMP": directory},
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(process.returncode, 7, process.stderr)
            self.assertNotIn("PRIVATE_VALUE", process.stdout)
            self.assertIn("Error: Running build hooks failed.", process.stdout)
            self.assertIn("Hash of downloaded file libsqlite3mc.x64.macos.dylib", process.stdout)
            summary = json.loads((root / "macos-build-timings.json").read_text())
            self.assertEqual(summary["exit_code"], 7)
            self.assertEqual([item["phase"] for item in summary["events"]], ["pod_install", "xcode_build"])
            self.assertIn("preparation_seconds", summary)
            self.assertFalse(list(root.glob("inboxplus-build-*")))

    def test_build_settings_queries_are_not_counted_as_compilation(self):
        self.assertIsNone(timing.phase("executing: xcodebuild -showBuildSettings -configuration Release"))
        self.assertEqual(timing.phase("executing: xcodebuild -workspace Runner.xcworkspace -configuration Release"), "xcode_build")
        self.assertEqual(timing.phase("Running pod install..."), "pod_install")
        self.assertEqual(timing.phase("Xcode is fetching Swift Package Manager dependencies"), "swiftpm_resolution")


if __name__ == "__main__":
    unittest.main()
