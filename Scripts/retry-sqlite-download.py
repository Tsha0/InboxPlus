#!/usr/bin/env python3
"""Retry rejected SQLite downloads without retrying application test failures."""

import re
import shutil
import subprocess
import sys
import time


def run_command(command):
    executable = shutil.which(command[0])
    if executable is None:
        raise FileNotFoundError(command[0])
    command = [executable, *command[1:]]
    for attempt in range(3):
        rejected_download = False
        hook_failed = False
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            for line in process.stdout:
                print(line, end="", flush=True)
                rejected_download |= bool(re.search(
                    r"Hash of downloaded file (?:lib)?sqlite3mc\.[\w.]+ is [a-f0-9]{64}, expected [a-f0-9]{64}", line,
                ))
                hook_failed |= "Building assets for package:sqlite3 failed" in line or "Running build hooks failed" in line
            result = process.wait()
        if result == 0 or not (rejected_download and hook_failed) or attempt == 2:
            return result
        print("SQLite rejected a download; retrying with checksum verification still enabled.", flush=True)
        time.sleep(2 * (attempt + 1))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: retry-sqlite-download.py <command> [arguments...]")
    sys.exit(run_command(sys.argv[1:]))
