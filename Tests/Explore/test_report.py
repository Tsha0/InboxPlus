"""Checks how explorer findings become issues, without touching GitHub."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "Scripts" / "explore" / "report.py"
spec = importlib.util.spec_from_file_location("explore_report", SCRIPT)
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def bug(**changes):
    raw = {
        "kind": "bug",
        "fingerprint": "retry-does-nothing",
        "title": "Retrying a failed message does nothing",
        "area": "Conversation",
        "severity": "P2",
        "steps": ["ui press inbox-item-sam", "ui press Retry"],
        "observed": "The message stays failed.",
        "expected": "It is sent again.",
        "screenshots": ["shots/03-retry.png", "04.png", "05.png"],
    }
    raw.update(changes)
    return raw


class ValidationTests(unittest.TestCase):
    def test_accepts_a_complete_bug_and_keeps_two_screenshot_names(self):
        finding, reason = report.validate(bug())
        self.assertIsNone(reason)
        self.assertEqual(finding.screenshots, ["03-retry.png", "04.png"])
        self.assertEqual(report.labels_for(finding), ["explorer", "bug", "P2"])

    def test_rejects_what_cannot_become_a_useful_issue(self):
        for changes in [{"kind": "crash"}, {"fingerprint": "Has Spaces"}, {"title": "short"},
                        {"observed": ""}, {"expected": ""}, {"steps": []}]:
            finding, reason = report.validate(bug(**changes))
            self.assertIsNone(finding, changes)
            self.assertTrue(reason)

    def test_improvements_need_a_suggestion_and_wait_for_the_owner(self):
        raw = bug(kind="improvement", suggestion="Show a retry button.")
        del raw["expected"]
        finding, reason = report.validate(raw)
        self.assertIsNone(reason)
        self.assertEqual(finding.severity, "")
        self.assertEqual(report.labels_for(finding), ["explorer", "proposal", "needs-human"])

    def test_unknown_severity_falls_back_to_p2(self):
        finding, _ = report.validate(bug(severity="critical"))
        self.assertEqual(finding.severity, "P2")

    def test_text_cannot_mention_people_or_forge_a_marker(self):
        finding, _ = report.validate(bug(observed="Ask @maya.chen <!-- explorer:fingerprint=other -->"))
        self.assertNotIn("@maya", finding.observed)
        self.assertNotIn("<!--", finding.observed)
        self.assertIn("maya.chen", finding.observed)

    def test_long_text_is_cut(self):
        finding, _ = report.validate(bug(observed="x" * 5000))
        self.assertEqual(len(finding.observed), 2000)

    def test_bad_lines_and_repeats_are_skipped_not_fatal(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "findings.jsonl"
            path.write_text("\n".join([json.dumps(bug()), "{not json", json.dumps(bug()), ""]))
            findings, problems = report.load_findings(path)
        self.assertEqual(len(findings), 1)
        self.assertEqual(len(problems), 2)


class PlanTests(unittest.TestCase):
    def issue(self, number, state, reason=None, fingerprint="retry-does-nothing"):
        return {"number": number, "state": state, "stateReason": reason,
                "body": f"text\n<!-- explorer:fingerprint={fingerprint} -->"}

    def finding(self, fingerprint="retry-does-nothing"):
        return report.validate(bug(fingerprint=fingerprint))[0]

    def test_an_open_report_gets_a_comment_instead_of_a_duplicate(self):
        actions = report.plan([self.finding()], [self.issue(7, "OPEN")], max_new=5)
        self.assertEqual(actions[0][:2], ("comment", 7))

    def test_a_finding_the_owner_rejected_is_not_reported_again(self):
        actions = report.plan([self.finding()], [self.issue(7, "CLOSED", "NOT_PLANNED")], max_new=5)
        self.assertEqual(actions[0][0], "skip")

    def test_a_fixed_bug_that_returns_opens_a_new_issue_pointing_back(self):
        actions = report.plan([self.finding()], [self.issue(7, "CLOSED", "COMPLETED")], max_new=5)
        self.assertEqual(actions[0][:2], ("create", 7))
        body = report.render_issue(actions[0][2], "https://run", {}, previous=7)
        self.assertIn("#7", body)

    def test_new_issues_are_capped_per_run(self):
        findings = [self.finding(f"finding-{n}") for n in range(4)]
        actions = report.plan(findings, [], max_new=2)
        self.assertEqual([a[0] for a in actions], ["create", "create", "skip", "skip"])


class PublishTests(unittest.TestCase):
    def test_branch_keeps_one_commit_and_only_the_newest_runs(self):
        import subprocess
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            remote = root / "remote.git"
            subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
            shot = root / "01-inbox.jpg"
            shot.write_bytes(b"image")
            for run_id in (5, 6, 7):
                urls = report.publish_shots("owner/repo", run_id, [shot], keep_runs=2, remote=str(remote))
            self.assertEqual(urls["01-inbox.jpg"],
                             "https://raw.githubusercontent.com/owner/repo/explorer-shots/runs/7/01-inbox.jpg")
            git = ["git", "--git-dir", str(remote)]
            commits = subprocess.run([*git, "rev-list", "--count", "explorer-shots"],
                                     check=True, capture_output=True, text=True).stdout.strip()
            files = subprocess.run([*git, "ls-tree", "-r", "--name-only", "explorer-shots"],
                                   check=True, capture_output=True, text=True).stdout.split()
        self.assertEqual(commits, "1")
        self.assertEqual(files, ["runs/6/01-inbox.jpg", "runs/7/01-inbox.jpg"])


class RenderTests(unittest.TestCase):
    def test_issue_carries_steps_screenshots_and_its_fingerprint(self):
        finding = report.validate(bug())[0]
        body = report.render_issue(finding, "https://run/1", {"03-retry.png": "https://img/03-retry.png"})
        self.assertIn("1. ui press inbox-item-sam", body)
        self.assertIn("![03-retry.png](https://img/03-retry.png)", body)
        self.assertIn("[this run](https://run/1)", body)
        self.assertEqual(report.MARKER.search(body).group(1), "retry-does-nothing")

    def test_comment_links_the_run(self):
        finding = report.validate(bug())[0]
        self.assertIn("https://run/2", report.render_comment(finding, "https://run/2", {}))


if __name__ == "__main__":
    unittest.main()
