#!/usr/bin/env python3
"""Write update configuration before signing; development bundles stay offline by default."""
from __future__ import annotations
import argparse
import base64
import os
from pathlib import Path
import plistlib
from urllib.parse import urlparse


def configure(app: Path, release: bool, environment: dict[str, str]) -> None:
    plist = app / "Contents/Info.plist"
    with plist.open("rb") as stream:
        info = plistlib.load(stream)
    enabled = release or environment.get("INBOXPLUS_ENABLE_UPDATES") == "1"
    feed = environment.get("INBOXPLUS_UPDATE_FEED_URL", "https://tsha0.github.io/InboxPlus/appcast.xml")
    key = environment.get("INBOXPLUS_UPDATE_PUBLIC_KEY", "")
    build = environment.get("INBOXPLUS_BUILD_NUMBER", "")
    if enabled:
        parsed = urlparse(feed)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError("INBOXPLUS_UPDATE_FEED_URL must be an HTTPS URL without credentials")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 32
        except ValueError:
            valid_key = False
        if not valid_key:
            raise ValueError("INBOXPLUS_UPDATE_PUBLIC_KEY must be a base64-encoded 32-byte Sparkle public key")
        if not build.isascii() or not build.isdecimal() or int(build) < 1:
            raise ValueError("INBOXPLUS_BUILD_NUMBER must be a positive increasing integer")
        info.update({
            "CFBundleVersion": build,
            "SUFeedURL": feed,
            "SUPublicEDKey": key,
            "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": True,
            "SUScheduledCheckInterval": 14400,
            "SUEnableSystemProfiling": False,
        })
    info["InboxPlusUpdatesEnabled"] = enabled
    with plist.open("wb") as stream:
        plistlib.dump(info, stream, fmt=plistlib.FMT_XML, sort_keys=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--release", action="store_true")
    arguments = parser.parse_args()
    try:
        configure(arguments.app, arguments.release, dict(os.environ))
    except ValueError as error:
        parser.exit(1, f"error: {error}\n")
