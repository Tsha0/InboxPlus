#!/usr/bin/env python3
"""Reject malformed feeds and publication from a different release or download host."""
import base64
from pathlib import Path
import re
import sys
from urllib.parse import quote, urlparse, unquote
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
# GitHub renames uploaded assets with other characters, which would break the feed's URLs.
ASSET_NAME = re.compile(r"[A-Za-z0-9._-]+")


def release_asset(url: str, repository: str, extension: str) -> str:
    """Returns the URL's release directory after checking it names an asset of this repository."""
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith(f"/{repository}/releases/download/"):
        raise ValueError("download is outside this repository's GitHub Releases")
    directory, _, name = unquote(parsed.path).rpartition("/")
    if not name.endswith(extension):
        raise ValueError(f"expected a {extension} update archive")
    if not ASSET_NAME.fullmatch(name):
        raise ValueError(f"GitHub would rename the asset {name}")
    return directory


def check_signature(enclosure: ET.Element) -> None:
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("missing Ed25519 archive signature")
    if int(enclosure.get("length", "0")) <= 0:
        raise ValueError("missing archive length")


def validate(path: Path, repository: str, tag: str, expected_build: str = "") -> None:
    root = ET.parse(path).getroot()
    if root.tag != "rss":
        raise ValueError("expected an RSS appcast")
    items = root.findall("./channel/item")
    if not items:
        raise ValueError("appcast has no releases")
    current_prefix = f"https://github.com/{repository}/releases/download/{quote(tag, safe='')}/"
    has_current_release = False
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ValueError("release has no download")
        url = enclosure.get("url", "")
        release = release_asset(url, repository, ".zip")
        version = enclosure.get(f"{{{SPARKLE}}}version") or item.findtext(f"{{{SPARKLE}}}version", "")
        if not version.isascii() or not version.isdecimal() or int(version) < 1:
            raise ValueError("missing positive build number")
        check_signature(enclosure)
        for delta in item.findall(f"{{{SPARKLE}}}deltas/enclosure"):
            if release_asset(delta.get("url", ""), repository, ".delta") != release:
                raise ValueError("a delta update is not published with its full update")
            source = delta.get(f"{{{SPARKLE}}}deltaFrom", "")
            if not source.isascii() or not source.isdecimal() or not 0 < int(source) < int(version):
                raise ValueError("a delta update has no earlier build to apply to")
            check_signature(delta)
        has_current_release |= url.startswith(current_prefix) and (not expected_build or version == expected_build)
    if not has_current_release:
        raise ValueError("appcast does not contain the release being published")


if __name__ == "__main__":
    try:
        validate(Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
    except (ValueError, ET.ParseError) as error:
        sys.exit(f"Invalid update feed: {error}")
