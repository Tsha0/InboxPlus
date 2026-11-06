import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
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

    def test_tampered_download_is_removed_without_becoming_available(self):
        response = io.BytesIO(b"tampered")
        response.url = "https://example.invalid/archive"
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            artifacts = (("fixture.7z", response.url, "0" * 64),)
            with patch.object(media_artifacts, "ARTIFACTS", artifacts), patch.object(
                media_artifacts.urllib.request, "urlopen", return_value=response
            ):
                with self.assertRaisesRegex(RuntimeError, "Downloaded media archive failed"):
                    media_artifacts.prepare(location)
            self.assertEqual(list(location.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
