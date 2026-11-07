import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


changes = load_script("ci-changes")
release = load_script("require-release-ci")
results = load_script("check-ci-results")


class CIRoutingTests(unittest.TestCase):
    def test_documentation_and_website_skip_native_work(self):
        result = changes.affected(["README.md", "docs/updates.md", "website/src/app.tsx"])
        self.assertFalse(any(result.values()))

    def test_shared_inputs_reach_every_platform(self):
        for path in (
            "native/connectors/main.go", "packages/inboxplus_storage/lib/store.dart",
            "apps/inboxplus_flutter/lib/main.dart", "apps/inboxplus_flutter/pubspec.lock",
            "docs/assets/inboxplus-logo.png", "docs/sbom.cdx.json",
            "docs/dependency-licenses.json", "Scripts/package-flutter-desktop.py",
            ".github/workflows/ci.yml", "Tests/Packaging/test_ci.py", "new-component/source.c",
        ):
            with self.subTest(path=path):
                self.assertTrue(all(changes.affected([path]).values()))

    def test_native_inputs_are_platform_scoped(self):
        for path, target in (
            ("native/imessage/Sources/main.swift", "macos"),
            ("native/updates/Package.resolved", "macos"),
            ("apps/inboxplus_flutter/windows/CMakeLists.txt", "windows"),
            ("apps/inboxplus_flutter/linux/runner/main.cc", "linux"),
            ("apps/inboxplus_flutter/ios/Runner/Info.plist", "ios"),
        ):
            with self.subTest(path=path):
                result = changes.affected([path])
                self.assertTrue(result.pop("code"))
                self.assertEqual({key for key, value in result.items() if value}, {target})

    def test_android_does_not_enable_automatic_native_builds(self):
        result = changes.affected(["apps/inboxplus_flutter/android/app/build.gradle.kts"])
        self.assertTrue(result.pop("code"))
        self.assertFalse(any(result.values()))

    def test_renames_include_the_deleted_input(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], text=True, timeout=30).strip()

            git("init", "-q")
            source = Path(directory) / "connector.go"
            source.write_text("package main\n")
            git("add", ".")
            base = git("write-tree")
            source.rename(Path(directory) / "README.md")
            git("add", "-A")
            head = git("write-tree")
            event = Path(directory) / "event.json"
            event.write_text(json.dumps({"before": base}))
            output = Path(directory) / "output"
            subprocess.run(
                [sys.executable, str(ROOT / "Scripts/ci-changes.py")], cwd=directory,
                env={**os.environ, "GITHUB_EVENT_PATH": str(event), "GITHUB_SHA": head,
                     "GITHUB_OUTPUT": str(output)}, check=True, timeout=30,
            )
            self.assertIn("code=true", output.read_text())
            self.assertIn("ios=true", output.read_text())
            (Path(directory) / "README.md").write_text("trailing whitespace  \n")
            git("add", "README.md")
            whitespace_head = git("write-tree")
            check = subprocess.run(
                ["git", "-C", directory, "diff", "--check", head, whitespace_head],
                capture_output=True, timeout=30,
            )
            self.assertNotEqual(check.returncode, 0)
            self.assertIn(b"trailing whitespace", check.stdout)
            self.assertEqual(git("diff", "--check"), "")


class CIResultTests(unittest.TestCase):
    def needs(self, targets=(), code=False, android=False):
        outputs = {key: str(value).lower() for key, value in {
            "code": code, "macos": "macos" in targets, "windows": "windows" in targets,
            "ios": "ios" in targets, "linux": "linux" in targets,
        }.items()}
        needs = {"changes": {"result": "success", "outputs": outputs}}
        for job, required in {
            "lint": True, "generated-files": code, "packaging-linux": code,
            "generated-macos": "macos" in targets, "messages": "macos" in targets,
            "updater": "macos" in targets, "packaging-macos": "macos" in targets,
            "packaging-windows": "windows" in targets,
            "macos": "macos" in targets, "windows": "windows" in targets, "linux": "linux" in targets,
            "ios": "ios" in targets, "android": android,
        }.items():
            needs[job] = {"result": "success" if required else "skipped"}
        return needs

    def test_documentation_only_accepts_intentional_skips(self):
        results.check_results(self.needs(), False)

    def test_each_platform_and_manual_full_run(self):
        for targets in (("macos",), ("linux",), ("windows",), ("ios",),
                        ("macos", "linux", "windows", "ios")):
            with self.subTest(targets=targets):
                results.check_results(self.needs(targets, code=True), False)
        results.check_results(self.needs(("macos", "linux", "windows", "ios"), True, True), True)

    def test_failed_cancelled_and_unexpectedly_skipped_jobs_fail(self):
        baseline = self.needs(("macos", "linux", "windows", "ios"), True, True)
        for job in baseline:
            for state in ("failure", "cancelled", "skipped"):
                with self.subTest(job=job, state=state):
                    needs = {key: dict(value) for key, value in baseline.items()}
                    needs[job]["result"] = state
                    with self.assertRaises(RuntimeError):
                        results.check_results(needs, True)

    def test_unselected_jobs_must_be_skipped(self):
        for state in ("success", "failure", "cancelled"):
            with self.subTest(state=state):
                needs = self.needs()
                needs["linux"]["result"] = state
                with self.assertRaises(RuntimeError):
                    results.check_results(needs, False)

    def test_missing_result_is_not_accepted(self):
        needs = self.needs()
        del needs["lint"]
        with self.assertRaises(KeyError):
            results.check_results(needs, False)


class ReleaseCIGateTests(unittest.TestCase):
    def run_record(self, **overrides):
        return {"id": 1, "head_sha": "release", "event": "push", "head_branch": "main",
                "status": "completed", "conclusion": "success", **overrides}

    def test_exact_main_commit_and_manual_runs_are_accepted(self):
        release.require_success([self.run_record()], "release")
        release.require_success([self.run_record(event="workflow_dispatch", head_branch="release")], "release")

    def test_missing_other_commit_and_pr_only_runs_are_rejected(self):
        for runs in ([], [self.run_record(head_sha="other")],
                     [self.run_record(event="pull_request")], [self.run_record(head_branch="other")]):
            with self.subTest(runs=runs), self.assertRaises(RuntimeError):
                release.require_success(runs, "release")

    def test_newer_failures_and_incomplete_runs_do_not_reuse_old_success(self):
        for state in ({"conclusion": "failure"}, {"conclusion": "cancelled"},
                      {"status": "in_progress", "conclusion": None}):
            with self.subTest(state=state), self.assertRaises(RuntimeError):
                release.require_success([self.run_record(), self.run_record(id=2, **state)], "release")


if __name__ == "__main__":
    unittest.main()
