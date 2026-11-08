#!/usr/bin/env python3
"""Build and sign a Flutter macOS release and its Sparkle feed without publishing it."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


desktop = load("package-flutter-desktop")
configuration = load("configure-updates")
feed = load("validate-update-feed")


def release_settings(environment, previous_feed):
    version, build = desktop.version()
    legacy = json.loads((ROOT / "native/updates/legacy-release.json").read_text())
    if int(build) <= int(legacy["build"]):
        raise ValueError("The build number must exceed the shipped 0.8.5 build")
    if environment.get("INBOXPLUS_UPDATE_PUBLIC_KEY", legacy["public_key"]) != legacy["public_key"]:
        raise ValueError("The Sparkle public key must preserve trust from 0.8.5")
    if environment.get("INBOXPLUS_UPDATE_FEED_URL", legacy["feed_url"]) != legacy["feed_url"]:
        raise ValueError("The update feed must remain discoverable by 0.8.5")
    tag = environment.get("INBOXPLUS_RELEASE_TAG", "v" + version)
    if tag != "v" + version:
        raise ValueError("The release tag must match pubspec.yaml")
    identity = environment.get("INBOXPLUS_SIGNING_IDENTITY", "")
    if not identity or identity == "-":
        raise ValueError("Set INBOXPLUS_SIGNING_IDENTITY to the existing release certificate")
    mode = environment.get("INBOXPLUS_RELEASE_SIGNING", "")
    if mode not in ("self-signed", "developer-id"):
        raise ValueError("INBOXPLUS_RELEASE_SIGNING must be self-signed or developer-id")
    if mode == "developer-id" and not environment.get("INBOXPLUS_NOTARY_PROFILE"):
        raise ValueError("Developer ID releases need INBOXPLUS_NOTARY_PROFILE")
    if previous_feed is not None:
        items = ET.parse(previous_feed).getroot().findall("./channel/item")
        if not items:
            raise ValueError("The previous appcast has no releases")
        for item in items:
            enclosure = item.find("enclosure")
            old_build = item.findtext(f"{{{feed.SPARKLE}}}version") or (
                enclosure.get(f"{{{feed.SPARKLE}}}version") if enclosure is not None else None
            )
            if old_build is None or not old_build.isascii() or not old_build.isdecimal() or int(old_build) <= 0:
                raise ValueError("The previous appcast has an invalid build number")
            if int(build) <= int(old_build):
                raise ValueError("The build number must exceed every previously published build")
    return version, build, tag, identity, mode


def sign_bundle(app, identity, hardened):
    flags = ["--timestamp", "--options", "runtime"] if hardened else []

    def sign(path, entitlements=None):
        command = ["codesign", "--force", "--sign", identity, *flags]
        if entitlements:
            command += ["--entitlements", str(entitlements)]
        else:
            command += ["--preserve-metadata=entitlements"]
        subprocess.run([*command, str(path)], check=True)

    paths = sorted(app.rglob("*"), key=lambda path: len(path.parts), reverse=True)
    for path in paths:
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as source:
            native = source.read(4) in desktop.MACH_MAGIC
        if native:
            sign(path)
    for path in paths:
        if not path.is_symlink() and path.is_dir() and path.suffix in (".framework", ".xpc", ".app", ".bundle"):
            sign(path)
    sign(app, ROOT / "apps/inboxplus_flutter/macos/Runner/Release.entitlements")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    requirement = subprocess.run(["codesign", "-d", "-r-", str(app)], capture_output=True, text=True, check=True)
    if "certificate" not in requirement.stderr + requirement.stdout:
        raise ValueError("The release signature must be tied to a certificate")


def package(output, previous_feed, bundle, environment):
    version, build, tag, identity, mode = release_settings(environment, previous_feed)
    if load("generate-sbom").generate() != (ROOT / "docs/sbom.cdx.json").read_text():
        raise ValueError("Regenerate docs/sbom.cdx.json before packaging a release")
    legacy = json.loads((ROOT / "native/updates/legacy-release.json").read_text())
    environment = {**environment, "INBOXPLUS_BUILD_NUMBER": build, "INBOXPLUS_RELEASE_VERSION": version,
                   "INBOXPLUS_UPDATE_PUBLIC_KEY": legacy["public_key"], "INBOXPLUS_UPDATE_FEED_URL": legacy["feed_url"]}
    subprocess.run(["swift", "package", "--package-path", str(ROOT / "native/updates"),
                    "--force-resolved-versions", "resolve"], check=True)
    if bundle is None:
        app_root = ROOT / "apps/inboxplus_flutter"
        subprocess.run(["flutter", "pub", "get", "--enforce-lockfile"], cwd=app_root, check=True)
        subprocess.run(["flutter", "build", "macos", "--release"], cwd=app_root, check=True)
        bundle = desktop.default_bundle("macos")
    desktop.verify_bundle("macos", bundle)
    output.mkdir(parents=True, exist_ok=True)
    archive_name = f"InboxPlus-{version}-{build}.zip"
    if (output / archive_name).exists():
        raise ValueError("Use a fresh output directory; published archive bytes must never be replaced")
    with tempfile.TemporaryDirectory(prefix=".macos-release-", dir=output) as temporary:
        staging = Path(temporary)
        app = staging / "Inbox+.app"
        subprocess.run(["ditto", str(bundle), str(app)], check=True)
        configuration.configure(app, True, environment)
        resources = app / "Contents/Resources"
        shutil.copy2(ROOT / "LICENSE", resources / "LICENSE")
        shutil.copy2(ROOT / "docs/sbom.cdx.json", resources / "sbom.cdx.json")
        sign_bundle(app, identity, mode == "developer-id")
        subprocess.run(["codesign", "--verify", "--strict", "-R", "=" + legacy["signing_requirement"], str(app)], check=True)
        archive = staging / archive_name
        if mode == "developer-id":
            submission = staging / "notarization.zip"
            desktop.write_archive("macos", app, submission)
            subprocess.run(["xcrun", "notarytool", "submit", str(submission), "--keychain-profile",
                            environment["INBOXPLUS_NOTARY_PROFILE"], "--wait"], check=True)
            subprocess.run(["xcrun", "stapler", "staple", str(app)], check=True)
            subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
            subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
        desktop.verify_bundle("macos", app)
        desktop.write_archive("macos", app, archive)
        if previous_feed is not None:
            shutil.copy2(previous_feed, staging / "appcast.xml")
        notes = ""
        if environment.get("INBOXPLUS_RELEASE_NOTES_FILE"):
            notes = Path(environment["INBOXPLUS_RELEASE_NOTES_FILE"]).read_text()
        notes += ("<p><strong>Upgrading from 0.8.5:</strong> This release replaces the previous app with the Flutter app. "
                  "Saved contacts and conversation choices are imported. Accounts must be reconnected. "
                  "Previous message history and staged files remain in the original profile and are not imported. "
                  "Finish pending work before updating.</p>")
        notes_file = staging / "release-notes.html"
        notes_file.write_text(notes)
        environment["INBOXPLUS_RELEASE_NOTES_FILE"] = str(notes_file)
        subprocess.run(["bash", str(ROOT / "Scripts/generate-update-feed.sh"), str(staging), tag],
                       env=environment, check=True)
        feed.validate(staging / "appcast.xml", "Tsha0/InboxPlus", tag, build)
        items = ET.parse(staging / "appcast.xml").getroot().findall("./channel/item")
        enclosure = next(item.find("enclosure") for item in items
                         if item.findtext(f"{{{feed.SPARKLE}}}version") == build
                         or item.find("enclosure").get(f"{{{feed.SPARKLE}}}version") == build)
        subprocess.run(["swift", "run", "--package-path", str(ROOT / "native/updates"),
                        "--force-resolved-versions", "verify-update", str(archive),
                        environment["INBOXPLUS_UPDATE_PUBLIC_KEY"], enclosure.get(f"{{{feed.SPARKLE}}}edSignature")], check=True)
        shutil.copy2(ROOT / "docs/sbom.cdx.json", staging / f"inboxplus-{version}.cdx.json")
        assets = [archive, staging / "appcast.xml", staging / f"inboxplus-{version}.cdx.json"]
        (staging / "SHA256SUMS.txt").write_text("".join(
            hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n" for path in assets
        ))
        for path in [*assets, staging / "SHA256SUMS.txt"]:
            shutil.copy2(path, output / path.name)
    return output / archive_name


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/macos-release")
    parser.add_argument("--previous-feed", type=Path, required=True,
                        help="The currently published stable appcast, preserved in the new feed")
    parser.add_argument("--bundle", type=Path, help="Package an already-built release app")
    arguments = parser.parse_args()
    try:
        print(package(arguments.output.resolve(), arguments.previous_feed, arguments.bundle, dict(os.environ)))
    except (OSError, ValueError, RuntimeError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
