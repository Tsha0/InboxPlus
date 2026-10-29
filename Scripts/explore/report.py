#!/usr/bin/env python3
"""Turns the explorer agent's findings into GitHub issues.

The agent writes one JSON object per line to findings.jsonl while it explores. This script runs
in a separate job: the agent never holds a GitHub token. It validates each finding, publishes the
screenshots it cites to the `explorer-shots` branch, then opens an issue for each new finding and
comments on the open issue for one already reported. A finding the owner closed as not planned is
not reported again.

    report.py --findings build/explore/findings.jsonl --repo owner/name --run-id 123 --run-url URL
"""
import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

MARKER = re.compile(r"<!-- explorer:fingerprint=([a-z0-9][a-z0-9-]{2,79}) -->")
FINGERPRINT = re.compile(r"[a-z0-9][a-z0-9-]{2,79}")
SHOTS_BRANCH = "explorer-shots"
LABELS = {
    "explorer": ("5319e7", "Found by the explorer agent clicking through the demo app"),
    "bug": ("d73a4a", "Something isn't working"),
    "proposal": ("c5def5", "An idea waiting for the owner"),
    "needs-human": ("fbca04", "Blocked on the owner"),
    "P1": ("b60205", "Broken for users"),
    "P2": ("d93f0b", "Wrong, with a workaround"),
    "P3": ("fef2c0", "Polish"),
}


@dataclass
class Finding:
    fingerprint: str
    kind: str
    title: str
    area: str
    severity: str
    steps: list
    observed: str
    expected: str
    why: str = ""
    screenshots: list = field(default_factory=list)


def clean(text, limit):
    """Agent text goes into a public issue: no hidden markers, no @mentions, bounded length."""
    text = str(text).replace("<!--", "").replace("-->", "")
    # A demo handle such as @maya.chen would otherwise notify a real GitHub user.
    text = re.sub(r"@(?=[A-Za-z0-9])", "@⁠", text)
    text = text.strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def validate(raw):
    """Returns (Finding, None) or (None, reason)."""
    if not isinstance(raw, dict):
        return None, "not an object"
    kind = raw.get("kind")
    if kind not in ("bug", "improvement"):
        return None, "kind must be bug or improvement"
    fingerprint = str(raw.get("fingerprint", ""))
    if not FINGERPRINT.fullmatch(fingerprint):
        return None, "fingerprint must be 3-80 lowercase letters, digits and dashes"
    title = clean(raw.get("title", ""), 120)
    if len(title) < 10:
        return None, "title is missing or too short"
    observed = clean(raw.get("observed", ""), 2000)
    expected_key = "expected" if kind == "bug" else "suggestion"
    expected = clean(raw.get(expected_key, ""), 2000)
    if not observed or not expected:
        return None, f"observed and {expected_key} are required"
    steps = raw.get("steps") or []
    if not isinstance(steps, list) or not steps:
        return None, "steps must be a non-empty list"
    severity = raw.get("severity", "P2") if kind == "bug" else ""
    if kind == "bug" and severity not in ("P1", "P2", "P3"):
        severity = "P2"
    shots = [Path(str(s)).name for s in (raw.get("screenshots") or []) if str(s).strip()][:2]
    return Finding(
        fingerprint=fingerprint,
        kind=kind,
        title=title,
        area=clean(raw.get("area", "General"), 40) or "General",
        severity=severity,
        steps=[clean(step, 300) for step in steps[:20]],
        observed=observed,
        expected=expected,
        why=clean(raw.get("why", ""), 1000),
        screenshots=shots,
    ), None


def load_findings(path):
    """Reads findings.jsonl, skipping bad lines and repeated fingerprints. Returns (findings, problems)."""
    findings, problems, seen = [], [], set()
    if not Path(path).exists():
        return findings, ["no findings file"]
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            raw = json.loads(line)
        except json.JSONDecodeError as error:
            problems.append(f"line {number}: not JSON ({error.msg})")
            continue
        finding, reason = validate(raw)
        if reason:
            problems.append(f"line {number}: {reason}")
        elif finding.fingerprint in seen:
            problems.append(f"line {number}: repeats {finding.fingerprint}")
        else:
            seen.add(finding.fingerprint)
            findings.append(finding)
    return findings, problems


def plan(findings, existing, max_new):
    """Decides, per finding, whether to open an issue, comment on one, or skip.

    `existing` is the explorer issues as `gh issue list --json number,state,stateReason,body`.
    Returns a list of (action, issue_number, finding, note).
    """
    by_fingerprint = {}
    for issue in existing:
        match = MARKER.search(issue.get("body") or "")
        if match:
            by_fingerprint.setdefault(match.group(1), []).append(issue)
    actions, created = [], 0
    for finding in findings:
        matches = by_fingerprint.get(finding.fingerprint, [])
        still_open = [i for i in matches if i.get("state") == "OPEN"]
        if still_open:
            actions.append(("comment", still_open[0]["number"], finding, "seen again"))
        elif any((i.get("stateReason") or "").upper() == "NOT_PLANNED" for i in matches):
            actions.append(("skip", None, finding, "the owner closed it as not planned"))
        elif created >= max_new:
            actions.append(("skip", None, finding, f"limit of {max_new} new issues per run"))
        else:
            previous = max((i["number"] for i in matches), default=None)
            actions.append(("create", previous, finding, "regression of a closed issue" if previous else "new"))
            created += 1
    return actions


def labels_for(finding):
    if finding.kind == "bug":
        return ["explorer", "bug", finding.severity]
    return ["explorer", "proposal", "needs-human"]


def images(finding, shot_urls):
    return "\n".join(f"![{name}]({shot_urls[name]})" for name in finding.screenshots if name in shot_urls)


def render_issue(finding, run_url, shot_urls, previous=None):
    steps = "\n".join(f"{n}. {step}" for n, step in enumerate(finding.steps, 1))
    if finding.kind == "bug":
        sections = [
            f"**Area:** {finding.area} · **Severity:** {finding.severity}",
            f"### Steps\n{steps}",
            f"### What happens\n{finding.observed}",
            f"### What should happen\n{finding.expected}",
        ]
    else:
        sections = [
            f"**Area:** {finding.area}",
            f"### What I noticed\n{finding.observed}",
            f"### Suggestion\n{finding.expected}",
            f"### How I got there\n{steps}",
        ]
    if finding.why:
        sections.append(f"### Why it matters\n{finding.why}")
    pictures = images(finding, shot_urls)
    if pictures:
        sections.append(f"### Screenshots\n{pictures}")
    if previous:
        sections.append(f"This was reported before in #{previous}, which is closed, and it happens again.")
    sections.append(
        "---\n"
        f"Found by the explorer agent in [this run]({run_url}), on the demo inbox: made-up data, no "
        "accounts. Steps use `Scripts/explore/ui.swift`; see `.claude/skills/explore/SKILL.md`.\n"
        f"<!-- explorer:fingerprint={finding.fingerprint} -->"
    )
    return "\n\n".join(sections)


def render_comment(finding, run_url, shot_urls):
    lines = [f"Seen again in [this explorer run]({run_url}).", "", finding.observed]
    pictures = images(finding, shot_urls)
    if pictures:
        lines += ["", pictures]
    return "\n".join(lines)


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True, **kwargs)


def auth_config():
    token = os.environ["GH_TOKEN"]
    basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    return ["-c", f"http.https://github.com/.extraheader=AUTHORIZATION: basic {basic}"]


def publish_shots(repo, run_id, files, keep_runs=60, remote=None):
    """Commits this run's screenshots to the explorer-shots branch and returns name -> URL.

    The branch is rewritten as a single commit holding only the newest runs, so it never grows
    without bound in anyone's clone. Images in old issues disappear after `keep_runs` runs.
    """
    if not files:
        return {}
    # Tests pass a local repository; GitHub needs the job's token.
    auth = [] if remote else auth_config()
    remote = remote or f"https://github.com/{repo}.git"
    work = Path(tempfile.mkdtemp(prefix="explorer-shots-"))
    git = ["git", *auth, "-C", str(work)]
    run(["git", "init", "-q", str(work)])
    fetched = subprocess.run([*git, "fetch", "-q", "--depth", "1", remote, SHOTS_BRANCH],
                             text=True, capture_output=True).returncode == 0
    if fetched:
        run([*git, "checkout", "-q", "FETCH_HEAD"])
    runs = work / "runs"
    destination = runs / str(run_id)
    destination.mkdir(parents=True, exist_ok=True)
    for path in files:
        shutil.copy(path, destination / path.name)
    numbered = sorted((d for d in runs.iterdir() if d.is_dir() and d.name.isdigit()), key=lambda d: int(d.name))
    for old in numbered[:-keep_runs]:
        shutil.rmtree(old)
    run([*git, "checkout", "-q", "--orphan", "snapshot"])
    run([*git, "add", "-A"])
    run([*git, "-c", "user.name=inboxplus-explorer", "-c", "user.email=explorer@users.noreply.github.com",
         "commit", "-q", "-m", f"Explorer screenshots up to run {run_id}"])
    run([*git, "push", "-q", "--force", remote, f"HEAD:refs/heads/{SHOTS_BRANCH}"])
    base = f"https://raw.githubusercontent.com/{repo}/{SHOTS_BRANCH}/runs/{run_id}"
    return {path.name: f"{base}/{path.name}" for path in files}


def resolve_shot(shots_dir, name):
    """The workflow converts screenshots to JPEG for issues; fall back to the file as cited."""
    for candidate in (shots_dir / (Path(name).stem + ".jpg"), shots_dir / name):
        if candidate.is_file():
            return candidate
    return None


def gh(*arguments):
    return run(["gh", *arguments]).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--findings", required=True)
    parser.add_argument("--shots-dir", default=None, help="folder holding the screenshots findings cite")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--max-new", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true", help="print what would happen; change nothing")
    options = parser.parse_args()

    findings, problems = load_findings(options.findings)
    for problem in problems:
        print(f"skipped: {problem}")
    if not findings:
        print("No findings to report.")
        return 0

    shots_dir = Path(options.shots_dir or Path(options.findings).parent)
    cited = {}
    for finding in findings:
        for name in finding.screenshots:
            path = resolve_shot(shots_dir, name)
            if path:
                cited[name] = path
    existing = [] if options.dry_run else json.loads(gh(
        "issue", "list", "--repo", options.repo, "--label", "explorer", "--state", "all",
        "--limit", "500", "--json", "number,state,stateReason,body"))
    actions = plan(findings, existing, options.max_new)

    if options.dry_run:
        urls = {name: f"(screenshot {path.name})" for name, path in cited.items()}
        for action, number, finding, note in actions:
            print(f"== {action} {number or ''} [{finding.fingerprint}] {finding.title} ({note})")
            if action == "create":
                print(render_issue(finding, options.run_url, urls, number))
        return 0

    for name, (color, description) in LABELS.items():
        gh("label", "create", name, "--repo", options.repo, "--color", color, "--description", description, "--force")
    published = publish_shots(options.repo, options.run_id, sorted(set(cited.values())))
    urls = {name: published[path.name] for name, path in cited.items()}
    with tempfile.TemporaryDirectory() as folder:
        body_file = Path(folder) / "body.md"
        for action, number, finding, note in actions:
            if action == "create":
                body_file.write_text(render_issue(finding, options.run_url, urls, number), encoding="utf-8")
                label_args = [arg for label in labels_for(finding) for arg in ("--label", label)]
                url = gh("issue", "create", "--repo", options.repo, "--title", finding.title,
                         "--body-file", str(body_file), *label_args).strip()
                print(f"opened {url} [{finding.fingerprint}] ({note})")
            elif action == "comment":
                body_file.write_text(render_comment(finding, options.run_url, urls), encoding="utf-8")
                gh("issue", "comment", str(number), "--repo", options.repo, "--body-file", str(body_file))
                print(f"commented on #{number} [{finding.fingerprint}] ({note})")
            else:
                print(f"skipped [{finding.fingerprint}] {finding.title}: {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
