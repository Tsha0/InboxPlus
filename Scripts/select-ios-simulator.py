#!/usr/bin/env python3
"""Choose an available iOS runtime and compatible iPhone for the launch test."""

import json
import re
import subprocess
import sys


def select_runtime_device(document):
    runtimes = [
        runtime for runtime in document["runtimes"]
        if runtime.get("isAvailable", True)
        and re.search(r"\.iOS-[0-9]+(-[0-9]+)*$", runtime["identifier"])
    ]
    if not runtimes:
        raise ValueError("No available iOS simulator runtime is installed")
    runtime = max(runtimes, key=lambda value: tuple(int(part) for part in value["version"].split(".")))
    phones = [device for device in runtime["supportedDeviceTypes"] if device["name"].startswith("iPhone ")]
    if not phones:
        raise ValueError("The latest iOS simulator runtime has no supported iPhone device type")

    def preference(device):
        match = re.fullmatch(r"iPhone (\d+) Pro", device["name"])
        return (match is not None, int(match.group(1)) if match else 0, device["name"])

    return runtime["identifier"], max(phones, key=preference)["identifier"]


def main():
    document = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "runtimes", "available", "--json"], text=True,
    ))
    try:
        print(*select_runtime_device(document))
    except ValueError as error:
        sys.exit(str(error))


if __name__ == "__main__":
    main()
