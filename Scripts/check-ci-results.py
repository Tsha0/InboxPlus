#!/usr/bin/env python3
"""Reject failed checks and skips that do not match the affected components."""

import json
import os


def check_results(needs, android):
    changes = needs["changes"]
    if changes["result"] != "success":
        raise RuntimeError("Change detection did not succeed.")
    outputs = changes["outputs"]
    selected = {key: outputs[key] == "true" for key in ("code", "macos", "windows", "linux", "ios")}
    expected = {
        "lint": True,
        "generated-files": selected["code"],
        "packaging-linux": selected["code"],
        "generated-macos": selected["macos"],
        "messages": selected["macos"],
        "updater": selected["macos"],
        "packaging-macos": selected["macos"],
        "packaging-windows": selected["windows"],
        "macos": selected["macos"],
        "windows": selected["windows"],
        "linux": selected["linux"],
        "ios": selected["ios"],
        "android": android,
    }
    errors = []
    for job, required in expected.items():
        result = needs[job]["result"]
        wanted = "success" if required else "skipped"
        if result != wanted:
            errors.append(f"{job}: expected {wanted}, got {result}")
    if errors:
        raise RuntimeError("\n".join(errors))


if __name__ == "__main__":
    check_results(json.loads(os.environ["CI_NEEDS"]), os.environ["ANDROID_BUILD"] == "true")
    print("All selected CI jobs passed; other jobs were intentionally skipped.")
