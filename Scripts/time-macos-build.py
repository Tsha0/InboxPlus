#!/usr/bin/env python3
"""Time Flutter preparation and Xcode without publishing verbose environment dumps."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


def phase(line):
    if "executing:" in line and "xcodebuild" in line and "-configuration" in line and "-showBuildSettings" not in line:
        return "xcode_build"
    if "Running pod install" in line:
        return "pod_install"
    if "Xcode is fetching Swift Package Manager dependencies" in line:
        return "swiftpm_resolution"
    return None


def main():
    started = time.monotonic()
    events = []
    xcode_started = None
    with tempfile.TemporaryDirectory(prefix="inboxplus-build-", dir=os.environ.get("RUNNER_TEMP")) as directory:
        log = Path(directory) / "verbose.log"
        with log.open("w") as output:
            process = subprocess.Popen(
                ["flutter", "build", "macos", "--release", "--verbose"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            for line in process.stdout:
                output.write(line)
                elapsed = time.monotonic() - started
                name = phase(line)
                if name:
                    events.append({"phase": name, "elapsed_seconds": round(elapsed, 3)})
                    print(f"macos_build_phase phase={name} elapsed_seconds={elapsed:.3f}", flush=True)
                    if name == "xcode_build":
                        xcode_started = elapsed
                connector = re.search(r"connector_(?:build|architecture_start|architecture_done)\s+.*", line)
                if connector:
                    print(connector.group(), flush=True)
                if "Built build/macos/" in line or re.search(
                    r"(?:error:|Error[: (]|BUILD FAILED|Bad state: Hash of downloaded file|Building assets for package:sqlite3 failed|Running build hooks failed)", line,
                ):
                    print(line.rstrip(), flush=True)
            result = process.wait()
        total = time.monotonic() - started
        summary = {"total_seconds": round(total, 3), "exit_code": result, "events": events}
        if xcode_started is not None:
            summary["preparation_seconds"] = round(xcode_started, 3)
            summary["xcode_and_postprocessing_seconds"] = round(total - xcode_started, 3)
        destination = Path(os.environ.get("RUNNER_TEMP", directory)) / "macos-build-timings.json"
        destination.write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary), flush=True)
        if result:
            print("macOS build failed; only filtered compiler errors are published to avoid verbose environment dumps.")
        return result


if __name__ == "__main__":
    raise SystemExit(main())
