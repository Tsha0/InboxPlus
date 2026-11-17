#!/usr/bin/env python3
"""Create the branded drag-to-Applications disk image on a macOS desktop session."""

import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

LAYOUT = '''
on run arguments
    set volumePath to item 1 of arguments
    tell application "Finder"
        set installer to folder ((POSIX file volumePath) as alias)
        open installer
        tell container window of installer
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            set bounds to {100, 100, 800, 528}
        end tell
        set viewOptions to icon view options of container window of installer
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 12
        set label position of viewOptions to bottom
        set shows item info of viewOptions to false
        set background picture of viewOptions to file ".background:installer.png" of installer
        set position of item "Inbox+.app" of installer to {210, 228}
        set position of item "Applications" of installer to {490, 228}
        close container window of installer
        open installer
        update installer without registering applications
        close container window of installer
    end tell
end run
'''


def detach(device):
    for attempt in range(5):
        if subprocess.run(["hdiutil", "detach", device], timeout=120).returncode == 0:
            return
        if attempt < 4:
            time.sleep(2)
    subprocess.run(["hdiutil", "detach", "-force", device], check=True, timeout=120)


def create(app, output):
    if output.exists():
        raise ValueError("The disk image already exists; use a fresh output path")
    if not (app / "Contents/Info.plist").is_file():
        raise ValueError("Expected a macOS application bundle")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".dmg-", dir=output.parent) as temporary:
        staging = Path(temporary)
        source = staging / "contents"
        background = source / ".background/installer.png"
        background.parent.mkdir(parents=True)
        subprocess.run(["ditto", str(app), str(source / "Inbox+.app")], check=True, timeout=300)
        (source / "Applications").symlink_to("/Applications")
        subprocess.run(["swift", str(ROOT / "Scripts/make-dmg-background.swift"),
                        str(ROOT / "website/assets/fonts/bricolage-grotesque-latin.woff2"),
                        str(background)], check=True, timeout=120)
        writable = staging / "installer.dmg"
        subprocess.run(["hdiutil", "create", "-ov", "-fs", "HFS+", "-format", "UDRW",
                        "-volname", "Inbox+", "-srcfolder", str(source), str(writable)],
                       check=True, timeout=300)
        attached = subprocess.run(["hdiutil", "attach", "-nobrowse", "-noautoopen", "-plist", str(writable)], capture_output=True,
                                  check=True, timeout=120)
        entities = plistlib.loads(attached.stdout)["system-entities"]
        volume = next(entity for entity in entities if "mount-point" in entity)
        mount = Path(volume["mount-point"])
        device = volume["dev-entry"]
        try:
            subprocess.run(["osascript", "-", str(mount)], input=LAYOUT, text=True, check=True, timeout=120)
            deadline = time.monotonic() + 30
            while not (mount / ".DS_Store").is_file() and time.monotonic() < deadline:
                time.sleep(0.1)
            subprocess.run(["sync"], check=True, timeout=30)
            if not (mount / ".DS_Store").is_file():
                raise ValueError("Finder did not save the installer layout")
        except BaseException as error:
            try:
                detach(device)
            except (OSError, subprocess.SubprocessError) as cleanup_error:
                error.add_note(f"Installer volume cleanup also failed: {cleanup_error}")
            raise
        else:
            detach(device)
        subprocess.run(["hdiutil", "convert", str(writable), "-format", "UDZO", "-o", str(output)],
                       check=True, timeout=300)
        subprocess.run(["hdiutil", "verify", str(output)], check=True, timeout=120)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    try:
        create(arguments.app.resolve(), arguments.output.resolve())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + "\n")
