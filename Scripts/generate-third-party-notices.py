#!/usr/bin/env python3
"""Bundle reviewed dependency license texts from the resolved source caches."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
specification = importlib.util.spec_from_file_location("inventory", ROOT / "Scripts/generate-sbom.py")
inventory = importlib.util.module_from_spec(specification)
specification.loader.exec_module(inventory)


def generate(pub_cache, go_cache, go_root):
    reviews = json.loads((ROOT / "docs/dependency-licenses.json").read_text())
    sections = [
        "Inbox+ third-party notices\n\n"
        "Inbox+ is distributed under AGPL-3.0-or-later.\n"
        "Source repository: https://github.com/Tsha0/InboxPlus\n\n"
        "These notices describe the repository's locked application and build dependencies. "
        "Some dependencies are platform-specific or used only during development. "
        "Flutter's license registry also includes Dart package notices.\n\n"
        + (ROOT / "LICENSE").read_text()
    ]
    for ecosystem, components, cache in (
        ("pub", inventory.pub_components(reviews), pub_cache / "hosted/pub.dev"),
        ("golang", inventory.go_components(reviews), go_cache),
    ):
        for component in sorted(components, key=lambda value: (value["name"], value["version"])):
            name, version = component["name"], component["version"]
            review = reviews[ecosystem + ":" + name + "@" + version]
            directory = cache / (name + ("-" if ecosystem == "pub" else "@") + version)
            texts = []
            for filename, expected in sorted(review["evidence"].items()):
                content = (directory / filename).read_bytes()
                if hashlib.sha256(content).hexdigest() != expected:
                    raise ValueError("Dependency license differs from reviewed source: " + name)
                texts.append(filename + "\n\n" + content.decode("utf-8", errors="replace"))
            if name == "github.com/beeper/poly1305":
                texts.append("The Go Authors' BSD license referenced by the source headers:\n\n" + (go_root / "LICENSE").read_text())
            sections.append(name + " " + version + "\n" + component["purl"] + "\n"
                            + review["license"] + "\n\n" + "\n\n".join(texts))
    component, = inventory.sparkle_component(reviews)
    review = reviews["swift:Sparkle@" + component["version"]]
    texts = []
    for filename, expected in sorted(review["evidence"].items()):
        content = (ROOT / "native/updates" / filename).read_bytes()
        if hashlib.sha256(content).hexdigest() != expected:
            raise ValueError("Sparkle license differs from the reviewed artifact")
        texts.append(content.decode("utf-8"))
    sections.append("Sparkle " + component["version"] + "\n" + component["purl"] + "\n"
                    + review["license"] + "\n\n" + "\n\n".join(texts))
    sections.append(
        "Native media components\n\n"
        "The media_kit plugin license covers its wrapper, not the native mpv, FFmpeg and codec libraries. "
        "Native source/configuration references for the exact selected artifacts:\n\n"
        "Apple libmpv video-default v0.6.0:\n"
        "https://github.com/media-kit/libmpv-darwin-build/tree/v0.6.0\n"
        "https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0\n\n"
        "Android libmpv default v1.1.7:\n"
        "https://github.com/media-kit/libmpv-android-video-build/tree/v1.1.7\n"
        "https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.7\n\n"
        "Windows libmpv 2023-09-24:\n"
        "https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24\n"
        "https://github.com/mpv-player/mpv/tree/652a1dd90711839acdccc08004056d25514ef2d8\n"
        "The selected FFmpeg DLL build reports LGPL version 3 or later.\n\n"
        "Windows ANGLE v1.0.1:\n"
        "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1\n"
        "https://chromium.googlesource.com/angle/angle/\n\n"
        "Linux libmpv is supplied by the operating system package manager.\n\n"
        "This development notice does not certify a complete native-library release source or relinking bundle. "
        "Before distribution, include the selected native builds' complete license texts, notices and "
        "corresponding source/relinking materials. See docs/dependencies.md in the source repository."
    )
    output = ("\n\n" + "=" * 78 + "\n\n").join(sections).replace("\r\n", "\n")
    return "\n".join(line.rstrip() for line in output.splitlines()) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "apps/inboxplus_flutter/assets/third_party_notices.txt")
    arguments = parser.parse_args()
    go_binary = os.environ.get("GO_BINARY", "go")
    go_cache = Path(subprocess.check_output([go_binary, "env", "GOMODCACHE"], text=True).strip())
    go_root = Path(subprocess.check_output([go_binary, "env", "GOROOT"], text=True).strip())
    pub_cache = Path(os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache")))
    output = generate(pub_cache, go_cache, go_root)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(output)
