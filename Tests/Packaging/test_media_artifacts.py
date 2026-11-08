import hashlib
import importlib.util
import io
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

    def test_application_failure_is_not_retried(self):
        result, attempts = self.run_fixture(download_error=False)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(attempts, 1)


if __name__ == "__main__":
    unittest.main()
