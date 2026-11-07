#!/usr/bin/env python3
"""Require a successful trusted CI run for the exact release commit."""

import json
import os
import subprocess


def require_success(runs, sha):
    eligible = [run for run in runs if run["head_sha"] == sha and (
        (run["event"] == "push" and run["head_branch"] == "main")
        or run["event"] == "workflow_dispatch"
    )]
    if not eligible:
        raise RuntimeError("Run CI on the release commit before releasing it.")
    latest = max(eligible, key=lambda run: run["id"])
    if latest["status"] != "completed" or latest["conclusion"] != "success":
        raise RuntimeError("The latest CI run for the release commit must finish successfully before release.")


def main():
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    repository = os.environ["GITHUB_REPOSITORY"]
    response = subprocess.check_output([
        "gh", "api", f"repos/{repository}/actions/workflows/ci.yml/runs?head_sha={sha}&per_page=100",
    ], text=True)
    require_success(json.loads(response)["workflow_runs"], sha)
    print(f"CI passed for release commit {sha}.")


if __name__ == "__main__":
    main()
