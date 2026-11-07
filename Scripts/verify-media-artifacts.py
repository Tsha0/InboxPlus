#!/usr/bin/env python3
"""Prepare SHA-256-verified archives before media-kit's CMake can extract them."""

import argparse
import hashlib
import os
from pathlib import Path
import tempfile
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
        descriptor, temporary = tempfile.mkstemp(prefix=name + ".", suffix=".tmp", dir=directory)
        try:
            with os.fdopen(descriptor, "wb") as output:
                with urllib.request.urlopen(url, timeout=120) as response:
                    if not response.url.startswith("https://"):
                        raise RuntimeError("Media archive redirected away from HTTPS")
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        output.write(chunk)
            if digest(Path(temporary)) != expected:
                raise RuntimeError("Downloaded media archive failed SHA-256 verification: " + name)
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("windows", "android"), required=True)
    parser.add_argument("--cache-dir", type=Path, required=True)
    arguments = parser.parse_args()
    prepare(arguments.cache_dir, ANDROID_ARTIFACTS if arguments.platform == "android" else ARTIFACTS)
