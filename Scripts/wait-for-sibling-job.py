#!/usr/bin/env python3
"""Block a release upload until a sibling job in the same run has succeeded."""

import json
import os
import subprocess
import sys
import time


def decide(jobs, name):
    matches = [job for job in jobs if job.get("name") == name]
    if not matches or matches[-1].get("status") != "completed":
        return "wait"
    conclusion = matches[-1].get("conclusion")
    if conclusion != "success":
        raise RuntimeError(f"{name} completed as {conclusion}")
    return "done"


def fetch_jobs(repository, run_id):
    payload = subprocess.check_output(
        ["gh", "api", f"repos/{repository}/actions/runs/{run_id}/jobs", "--jq", "."],
        text=True,
    )
    return json.loads(payload)["jobs"]


def wait_for_job(fetch, name, attempts, pause):
    for _ in range(attempts):
        if decide(fetch(), name) == "done":
            return
        time.sleep(pause)
    raise RuntimeError(f"{name} did not finish")


def main():
    name = sys.argv[1]
    wait_for_job(
        lambda: fetch_jobs(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_RUN_ID"]),
        name, attempts=240, pause=15,
    )
    print(f"sibling_job name={name} result=success")


if __name__ == "__main__":
    main()
