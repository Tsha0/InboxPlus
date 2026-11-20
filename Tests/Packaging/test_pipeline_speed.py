import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


deps = load_script("install-linux-desktop-deps")
sibling = load_script("wait-for-sibling-job")


class LinuxPackageMirrorTests(unittest.TestCase):
    def test_chooses_the_fastest_mirror_and_rewrites_archive_uris(self):
        mirror = deps.choose_mirror((
            ("http://us-east-2.ec2.archive.ubuntu.com/ubuntu", 342_000),
            ("http://archive.ubuntu.com/ubuntu", 20_000_000),
            ("http://azure.archive.ubuntu.com/ubuntu", None),
        ))
        self.assertEqual(mirror, "http://archive.ubuntu.com/ubuntu")
        original = "\n".join((
            "URIs: http://us-east-2.ec2.archive.ubuntu.com/ubuntu/",
            "URIs: http://security.ubuntu.com/ubuntu/",
            "deb http://azure.archive.ubuntu.com/ubuntu noble main",
        ))
        rewritten = deps.rewrite_archive_uris(original, mirror)
        self.assertIn("URIs: http://archive.ubuntu.com/ubuntu/", rewritten)
        self.assertIn("URIs: http://security.ubuntu.com/ubuntu/", rewritten)
        self.assertIn("deb http://archive.ubuntu.com/ubuntu/ noble main", rewritten)
        self.assertNotIn("ec2.archive", rewritten)

    def test_failed_probes_do_not_choose_a_mirror(self):
        with self.assertRaises(RuntimeError):
            deps.choose_mirror((("http://archive.ubuntu.com/ubuntu", None),))

    def test_cached_debs_are_restored_once_and_new_debs_are_stored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "cache"
            archives = root / "archives"
            cache.mkdir()
            archives.mkdir()
            (cache / "webkit.deb").write_bytes(b"cached")
            self.assertEqual(deps.restore_debs(cache, archives), 1)
            self.assertEqual(deps.restore_debs(cache, archives), 0)
            (archives / "gtk.deb").write_bytes(b"new")
            self.assertEqual(deps.store_debs(archives, cache), 1)
            self.assertEqual((cache / "gtk.deb").read_bytes(), b"new")


class SiblingJobTests(unittest.TestCase):
    def test_upload_waits_for_success_and_rejects_failure(self):
        self.assertEqual(sibling.decide([], "iOS / Launch test"), "wait")
        self.assertEqual(sibling.decide(
            [{"name": "iOS / Launch test", "status": "in_progress"}], "iOS / Launch test",
        ), "wait")
        self.assertEqual(sibling.decide(
            [{"name": "iOS / Launch test", "status": "completed", "conclusion": "success"}],
            "iOS / Launch test",
        ), "done")
        with self.assertRaises(RuntimeError):
            sibling.decide(
                [{"name": "Verify macOS release", "status": "completed", "conclusion": "failure"}],
                "Verify macOS release",
            )


if __name__ == "__main__":
    unittest.main()
