#!/usr/bin/env python3
"""Retry rejected SQLite downloads without retrying application test failures."""

import json
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import time


def prepare_rejected_download(filename, expected, project=Path.cwd()):
    for configuration in (project / ".dart_tool/hooks_runner/sqlite3").glob("*/input.json"):
        hook = json.loads(configuration.read_text())
        hashes = (Path(hook["package_root"]) / "lib/src/hook/asset_hashes.dart").read_text()
        pinned = re.search(r"'" + re.escape(filename) + r"': '([a-f0-9]{64})'", hashes)
        if pinned is None or pinned.group(1) != expected:
            continue
        code = hook["config"]["extensions"]["code_assets"]
        if f".{code['target_architecture']}." not in filename:
            continue
        os_name = code["target_os"]
        if f".{os_name}." not in filename and not (os_name == "ios" and ".ios_sim." in filename):
            continue
        release = re.search(r"releaseTag = '([^']+)'", hashes).group(1)
        local_name = "sqlite3mc.dll" if os_name == "windows" else "libsqlite3mc.dylib" if os_name in {"ios", "macos"} else "libsqlite3mc.so"
        destination = Path(hook["out_dir_shared"]) / ("download-" + expected[:8])
        media = runpy.run_path(str(Path(__file__).with_name("verify-media-artifacts.py")))
        media["prepare"](destination, ((local_name,
            f"https://github.com/simolus3/sqlite3.dart/releases/download/{release}/{filename}", expected),))
        return


def run_command(command):
    executable = shutil.which(command[0])
    if executable is None:
        raise FileNotFoundError(command[0])
    if executable.lower().endswith('.exe'):
        executable = executable[:-4] + '.exe'
    command = [executable, *command[1:]]
    for attempt in range(3):
        rejected_download = None
        hook_failed = False
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            for line in process.stdout:
                print(line, end="", flush=True)
                rejected = re.search(
                    r"Hash of downloaded file ((?:lib)?sqlite3mc\.[\w.]+) is [a-f0-9]{64}, expected ([a-f0-9]{64})", line,
                )
                if rejected:
                    rejected_download = rejected.groups()
                hook_failed |= "Building assets for package:sqlite3 failed" in line or "Running build hooks failed" in line
            result = process.wait()
        if result == 0 or not (rejected_download and hook_failed) or attempt == 2:
            return result
        print("SQLite rejected a download; retrying with checksum verification still enabled.", flush=True)
        prepare_rejected_download(*rejected_download)
        time.sleep(2 * (attempt + 1))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: retry-sqlite-download.py <command> [arguments...]")
    sys.exit(run_command(sys.argv[1:]))
