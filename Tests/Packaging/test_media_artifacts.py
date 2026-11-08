import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
import urllib.error
from unittest.mock import patch


script = Path(__file__).resolve().parents[2] / "Scripts" / "verify-media-artifacts.py"
specification = importlib.util.spec_from_file_location("media_artifacts", script)
media_artifacts = importlib.util.module_from_spec(specification)
specification.loader.exec_module(media_artifacts)


class MediaArtifactsTests(unittest.TestCase):
    def test_verified_cache_does_not_download(self):
        payload = b"fixture archive"
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            (location / "fixture.7z").write_bytes(payload)
            artifacts = (("fixture.7z", "https://example.invalid/archive", hashlib.sha256(payload).hexdigest()),)
            with patch.object(media_artifacts, "ARTIFACTS", artifacts), patch.object(
                media_artifacts.urllib.request, "urlopen"
            ) as download:
                media_artifacts.prepare(location)
                download.assert_not_called()

    def test_tampered_cache_fails_before_download(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            (location / "fixture.7z").write_bytes(b"tampered")
            artifacts = (("fixture.7z", "https://example.invalid/archive", "0" * 64),)
            with patch.object(media_artifacts, "ARTIFACTS", artifacts), patch.object(
                media_artifacts.urllib.request, "urlopen"
            ) as download:
                with self.assertRaisesRegex(RuntimeError, "Cached media archive failed"):
                    media_artifacts.prepare(location)
                download.assert_not_called()

    def response(self, payload):
        response = io.BytesIO(payload)
        response.url = "https://example.invalid/archive"
        return response

    def test_tampered_download_is_removed_without_becoming_available(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            artifacts = (("fixture.7z", "https://example.invalid/archive", "0" * 64),)
            with patch.object(media_artifacts.urllib.request, "urlopen", side_effect=lambda *a, **k: self.response(b"tampered")) as download, \
                    patch.object(media_artifacts.time, "sleep"):
                with self.assertRaisesRegex(RuntimeError, "Downloaded media archive failed"):
                    media_artifacts.prepare(location, artifacts)
            self.assertEqual(download.call_count, 3)
            self.assertEqual(list(location.iterdir()), [])

    def test_transient_http_error_or_error_page_never_becomes_an_archive(self):
        payload = b"verified archive"
        for rejected in (
            urllib.error.HTTPError("https://example.invalid/archive", 503, "unavailable", {}, None),
            self.response(b"proxy error page"),
        ):
            with self.subTest(rejected=type(rejected).__name__), tempfile.TemporaryDirectory() as directory:
                location = Path(directory)
                artifacts = (("fixture.tar.gz", "https://example.invalid/archive", hashlib.sha256(payload).hexdigest()),)
                with patch.object(media_artifacts.urllib.request, "urlopen", side_effect=[rejected, self.response(payload)]) as download, \
                        patch.object(media_artifacts.time, "sleep"):
                    media_artifacts.prepare(location, artifacts)
                self.assertEqual(download.call_count, 2)
                self.assertEqual((location / "fixture.tar.gz").read_bytes(), payload)
                self.assertEqual(len(list(location.iterdir())), 1)

    def test_github_api_download_still_requires_the_pinned_checksum(self):
        payload = b"verified API archive"
        url = "https://github.com/fixture/native/releases/download/v1/archive.zip"
        for valid in [True, False]:
            with self.subTest(valid=valid), tempfile.TemporaryDirectory() as directory:
                location = Path(directory)
                artifacts = (("archive.zip", url, hashlib.sha256(payload).hexdigest()),)

                def api_download(command, **kwargs):
                    kwargs["stdout"].write(payload if valid else b"unverified")
                    return subprocess.CompletedProcess(command, 0)

                with patch.object(media_artifacts.urllib.request, "urlopen", side_effect=urllib.error.HTTPError(url, 504, "timeout", {}, None)), \
                        patch.object(media_artifacts.shutil, "which", return_value="gh"), \
                        patch.object(media_artifacts.subprocess, "check_output", return_value=json.dumps({"assets": [{"id": 7, "name": "archive.zip"}]})), \
                        patch.object(media_artifacts.subprocess, "run", side_effect=api_download), \
                        patch.object(media_artifacts.time, "sleep"):
                    if valid:
                        media_artifacts.prepare(location, artifacts)
                        self.assertEqual((location / "archive.zip").read_bytes(), payload)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "SHA-256 verification"):
                            media_artifacts.prepare(location, artifacts)
                        self.assertEqual(list(location.iterdir()), [])


class SqliteDownloadRetryTests(unittest.TestCase):
    def run_fixture(self, *, download_error, permanent=False):
        with tempfile.TemporaryDirectory() as directory:
            counter = Path(directory) / "attempts"
            messages = (
                "Hash of downloaded file libsqlite3mc.x64.linux.so is " + "0" * 64 + ", expected " + "1" * 64
                + "\nBuilding assets for package:sqlite3 failed."
                if download_error else "An application test failed."
            )
            program = (
                "from pathlib import Path; import sys; "
                f"counter = Path({str(counter)!r}); "
                "attempt = int(counter.read_text()) + 1 if counter.exists() else 1; "
                "counter.write_text(str(attempt)); "
                f"print({messages!r}); "
                f"sys.exit(65 if {permanent!r} or attempt < 3 else 0)"
            )
            retry = script.parent / "retry-sqlite-download.py"
            result = subprocess.run([sys.executable, str(retry), sys.executable, "-c", program],
                                    capture_output=True, text=True, timeout=60)
            return result, int(counter.read_text())

    def test_rejected_download_is_retried_until_verified_hook_succeeds(self):
        result, attempts = self.run_fixture(download_error=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(attempts, 3)

    def test_repeated_checksum_failure_still_fails(self):
        result, attempts = self.run_fixture(download_error=True, permanent=True)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(attempts, 3)

    def test_cache_recovery_uses_pinned_package_hashes_and_hook_output_directory(self):
        spec = importlib.util.spec_from_file_location("sqlite_retry", script.parent / "retry-sqlite-download.py")
        retry = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(retry)
        expected = "1" * 64
        filename = "libsqlite3mc.x64.linux.so"
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            package = project / "package"
            hashes = package / "lib/src/hook/asset_hashes.dart"
            hashes.parent.mkdir(parents=True)
            hashes.write_text(f"const String? releaseTag = 'sqlite3-fixture';\nconst hashes = {{'{filename}': '{expected}'}};")
            hook = project / ".dart_tool/hooks_runner/sqlite3/fixture/input.json"
            hook.parent.mkdir(parents=True)
            shared = project / "shared"
            hook.write_text(json.dumps({
                "package_root": str(package), "out_dir_shared": str(shared),
                "config": {"extensions": {"code_assets": {"target_os": "linux", "target_architecture": "x64"}}},
            }))
            with patch.object(retry.runpy, "run_path", return_value={"prepare": lambda *args: None}) as loader:
                retry.prepare_rejected_download(filename, "0" * 64, project)
                loader.assert_not_called()
            calls = []
            with patch.object(retry.runpy, "run_path", return_value={"prepare": lambda *args: calls.append(args)}):
                retry.prepare_rejected_download(filename, expected, project)
            self.assertEqual(calls, [(shared / ("download-" + expected[:8]), ((
                "libsqlite3mc.so", f"https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-fixture/{filename}", expected,
            ),))])

    def test_application_failure_is_not_retried(self):
        result, attempts = self.run_fixture(download_error=False)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(attempts, 1)


if __name__ == "__main__":
    unittest.main()
