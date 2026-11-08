#!/usr/bin/env python3
"""Route committed changes to the platforms that consume them."""

import json
import os
from pathlib import Path
import subprocess


PLATFORMS = {"macos", "linux", "windows", "ios"}


def affected(paths):
    targets = set()
    code = False
    for path in paths:
        if path.startswith("website/") or path.endswith(".md"):
            continue
        code = True
        if path.startswith("native/imessage/") or path.startswith("native/updates/"):
            targets.add("macos")
        elif path.startswith("apps/inboxplus_flutter/"):
            component = path.split("/")[2]
            if component in PLATFORMS:
                targets.add(component)
            elif component != "android":
                targets.update(PLATFORMS)
        else:
            targets.update(PLATFORMS)
    return {"code": code, **{target: target in targets for target in sorted(PLATFORMS)}}


def changed_paths(base, head):
    if not base or set(base) == {"0"}:
        command = ["git", "ls-tree", "-r", "--name-only", "-z", head]
    else:
        command = ["git", "diff", "--name-only", "--no-renames", "-z", base, head]
    return [path for path in subprocess.check_output(command).decode().split("\0") if path]


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    head = os.environ["GITHUB_SHA"]
    base = event.get("before", "")
    if "pull_request" in event:
        head = event["pull_request"]["head"]["sha"]
        base = subprocess.check_output([
            "git", "merge-base", event["pull_request"]["base"]["sha"], head,
        ], text=True).strip()
    result = affected(changed_paths(base, head))
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        for key, value in {**result, "base": base, "head": head}.items():
            output.write(f"{key}={json.dumps(value) if not isinstance(value, str) else value}\n")


if __name__ == "__main__":
    main()
