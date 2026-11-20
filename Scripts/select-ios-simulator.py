#!/usr/bin/env python3
"""Choose an available iOS runtime and boot a clean iPhone simulator."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path


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


def existing_simulator(document, runtime_id, device_type):
    for device in document.get("devices", {}).get(runtime_id, []):
        if device.get("deviceTypeIdentifier") != device_type or device.get("isAvailable", True) is False:
            continue
        return device["udid"]
    return None


def boot_simulator(run, runtimes, devices):
    runtime, device_type = select_runtime_device(runtimes)
    udid = existing_simulator(devices, runtime, device_type)
    if udid is None:
        udid = run(["xcrun", "simctl", "create", "Inbox+ launch test", device_type, runtime]).strip()
    else:
        run(["xcrun", "simctl", "shutdown", udid])
        run(["xcrun", "simctl", "erase", udid])
    run(["xcrun", "simctl", "boot", udid])
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    return udid


def daemonize():
    if os.fork():
        os._exit(0)
    os.setsid()
    if os.fork():
        os._exit(0)


def boot_to(destination):
    def run(command):
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        if completed.returncode and not (command[1:3] == ["simctl", "shutdown"]):
            raise RuntimeError(completed.stderr.strip() or " ".join(command))
        return completed.stdout

    runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "available", "--json"]))
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    udid = boot_simulator(run, runtimes, devices)
    temporary = destination.with_suffix(".partial")
    temporary.write_text(udid + "\n")
    temporary.replace(destination)


def main():
    if "--boot" in sys.argv:
        destination = Path(sys.argv[-1])
        if "--foreground" not in sys.argv:
            daemonize()
        log = destination.with_suffix(".log").open("w")
        os.dup2(log.fileno(), 1)
        os.dup2(log.fileno(), 2)
        try:
            boot_to(destination)
        except Exception as error:
            destination.with_suffix(".failed").write_text(str(error) + "\n")
            sys.exit(str(error))
        return
    document = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "runtimes", "available", "--json"], text=True,
    ))
    try:
        print(*select_runtime_device(document))
    except ValueError as error:
        sys.exit(str(error))


if __name__ == "__main__":
    main()
