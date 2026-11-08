#!/usr/bin/env python3
"""Prepare SHA-256-verified archives before media-kit's CMake can extract them."""

import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request


ARTIFACTS = (
    (
        "mpv-dev-x86_64-20230924-git-652a1dd.7z",
        "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/"
        "mpv-dev-x86_64-20230924-git-652a1dd.7z",
        "dce982222d7a23e4a1c6f0fb6cc39f6e899a6714624b95ea49cff6558ee97572",
    ),
    (
        "ANGLE.7z",
        "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/"
        "releases/download/v1.0.1/ANGLE.7z",
        "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a",
    ),
)

ANDROID_ARTIFACTS = tuple(
    (
        "default-" + abi + ".jar",
        "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/default-" + abi + ".jar",
        checksum,
    )
    for abi, checksum in (
        ("arm64-v8a", "4363dfa5d3d415b91c1f16f6fb90c3fe59a77dfd3f9b824d2b24b492d6b09df9"),
        ("armeabi-v7a", "8ead114fc5a43348d89dc0eb8f41823e549b15115c29f73ee26973f973620995"),
        ("x86_64", "90268cd15f0766e07fb8e427388c621161177c9eb343c544f327bd63232bb236"),
        ("x86", "94c13cb6188b774710e5e487afff6e500c4af504df74b2494d7b12cf9be8a66a"),
    )
)


APPLE_ARTIFACTS = {
    platform: ((
        f"libmpv-xcframeworks-v0.6.0-{platform}-universal.tar.gz",
        f"https://github.com/media-kit/libmpv-darwin-build/releases/download/v0.6.0/"
        f"libmpv-xcframeworks_v0.6.0_{platform}-universal-video-default.tar.gz",
        checksum,
    ),)
    for platform, checksum in (
        ("ios", "a95bc18508af26136b8a408341c05b5585d644ec013f00ac07db09d2e28d36ae"),
        ("macos", "84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6"),
    )
}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def prepare(directory, artifacts=None):
    directory.mkdir(parents=True, exist_ok=True)
    for name, url, expected in ARTIFACTS if artifacts is None else artifacts:
        destination = directory / name
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or digest(destination) != expected:
                raise RuntimeError("Cached media archive failed SHA-256 verification: " + name)
            continue
        for attempt in range(3):
            try:
                download(directory, name, url, expected)
                break
            except (OSError, RuntimeError, http.client.HTTPException, subprocess.SubprocessError):
                if attempt == 2:
                    raise
                print(f"Media download did not verify; retrying {name} ({attempt + 2}/3).", flush=True)
                time.sleep(2 * (attempt + 1))


def download(directory, name, url, expected):
    destination = directory / name
    descriptor, temporary = tempfile.mkstemp(prefix=name + ".", suffix=".tmp", dir=directory)
    try:
        try:
            with os.fdopen(descriptor, "wb") as output:
                with urllib.request.urlopen(url, timeout=120) as response:
                    if not response.url.startswith("https://"):
                        raise RuntimeError("Media archive redirected away from HTTPS")
                    shutil.copyfileobj(response, output)
            if digest(Path(temporary)) != expected:
                raise RuntimeError("Downloaded media archive failed SHA-256 verification: " + name)
        except (OSError, RuntimeError, http.client.HTTPException):
            match = re.fullmatch(r"https://github.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/?]+)", url)
            if match is None or shutil.which("gh") is None:
                raise
            owner, repository, tag, filename = match.groups()
            release = json.loads(subprocess.check_output(
                ["gh", "api", f"repos/{owner}/{repository}/releases/tags/{tag}"], text=True, timeout=120,
            ))
            asset = next(item for item in release["assets"] if item["name"] == filename)
            with open(temporary, "wb") as output:
                subprocess.run(
                    ["gh", "api", "-H", "Accept: application/octet-stream",
                     f"repos/{owner}/{repository}/releases/assets/{asset['id']}"],
                    stdout=output, check=True, timeout=120,
                )
            if digest(Path(temporary)) != expected:
                raise RuntimeError("Downloaded media archive failed SHA-256 verification: " + name)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("windows", "android", "ios", "macos", "sparkle"), required=True)
    parser.add_argument("--cache-dir", type=Path, required=True)
    arguments = parser.parse_args()
    artifacts = {"windows": ARTIFACTS, "android": ANDROID_ARTIFACTS, **APPLE_ARTIFACTS}
    if arguments.platform == "sparkle":
        sparkle = json.loads((Path(__file__).resolve().parents[1] / "native/updates/sparkle-artifact.json").read_text())
        artifacts["sparkle"] = ((re.sub(r"[^a-zA-Z0-9]", "_", sparkle["url"]), sparkle["url"], sparkle["sha256"]),)
    prepare(arguments.cache_dir, artifacts[arguments.platform])
