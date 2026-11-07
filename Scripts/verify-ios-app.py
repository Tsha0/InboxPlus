#!/usr/bin/env python3
"""Check an archived or signed iOS build before it can reach TestFlight.

The Dart side finds the embedded connectors by symbol name, and archiving strips
those names unless the Runner target keeps global symbols. A stripped build
still launches; it just shows every network as unavailable.
"""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "apps/inboxplus_flutter/pubspec.yaml"
CONNECTOR_SYMBOLS = ("_inboxplus_request", "_inboxplus_poll_event", "_inboxplus_free")


def app_version():
    match = re.search(r"^version:\s*([^+\s]+)\+(\d+)\s*$", PUBSPEC.read_text(), re.M)
    if not match:
        sys.exit(f"{PUBSPEC} has no 'version: X.Y.Z+N' line")
    return match.group(1), match.group(2)


def problems(app, distribution):
    found = []
    exports = subprocess.run(
        ["xcrun", "dyld_info", "-exports", str(app / "Runner")],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    exported = set(re.findall(r"^\s*0x[0-9A-Fa-f]+\s+(\S+)", exports, re.M))
    missing = [name for name in CONNECTOR_SYMBOLS if name not in exported]
    if missing:
        found.append(
            "Runner does not export " + ", ".join(missing)
            + "; keep STRIP_STYLE = non-global on the Runner target"
        )
    if not (app / "PrivacyInfo.xcprivacy").is_file():
        found.append("PrivacyInfo.xcprivacy is missing; App Store Connect rejects the upload")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    built = (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
    expected = app_version()
    if built != expected:
        found.append(
            f"the app is {built[0]} ({built[1]}) but pubspec.yaml says {expected[0]} ({expected[1]})"
        )
    if distribution:
        verify = subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(app)],
            capture_output=True,
            text=True,
        )
        if verify.returncode:
            found.append("the signature does not verify: " + verify.stderr.strip())
        details = subprocess.run(
            ["codesign", "-dvv", str(app)], capture_output=True, text=True
        ).stderr
        if "Authority=Apple Distribution:" not in details:
            found.append("the app is not signed with an Apple Distribution certificate")
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path, help="an .ipa, an .xcarchive or a Runner.app")
    parser.add_argument(
        "--distribution",
        action="store_true",
        help="also require a valid App Store distribution signature",
    )
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temp:
        if args.build.suffix == ".ipa":
            subprocess.run(["ditto", "-x", "-k", str(args.build), temp], check=True)
            app = Path(temp, "Payload/Runner.app")
        elif args.build.suffix == ".xcarchive":
            app = args.build / "Products/Applications/Runner.app"
        else:
            app = args.build
        found = problems(app, args.distribution)
    for problem in found:
        print(f"error: {problem}", file=sys.stderr)
    if found:
        sys.exit(1)
    print(f"{args.build.name}: connectors exported, privacy manifest present, version matches")


if __name__ == "__main__":
    main()
