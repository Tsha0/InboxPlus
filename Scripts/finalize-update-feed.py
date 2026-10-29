#!/usr/bin/env python3
"""Keep published feed entries exactly as released and give new delta archives GitHub-safe names.

generate_appcast rewrites the entry of every archive it is shown. Older archives are only there so
it can build deltas, so their entries go back to the published text: otherwise their download URLs
would move to the new release, where those archives do not exist. GitHub renames uploaded assets
containing characters such as "+", so "Inbox+102-101.delta" becomes "InboxPlus-102-101.delta".
"""
from pathlib import Path
import re
import sys

ITEM = re.compile(r"<item>.*?</item>", re.DOTALL)
VERSION = re.compile(r"<sparkle:version>(\d+)</sparkle:version>")
DELTA = re.compile(r".*?(\d+)-(\d+)\.delta")


def version(item: str) -> str:
    match = VERSION.search(item)
    if not match:
        raise ValueError("feed item has no build number")
    return match.group(1)


def finalize(stage: Path, previous: str, build: str, prefix: str) -> None:
    feed = stage / "appcast.xml"
    text = feed.read_text()
    published = {version(item): item for item in ITEM.findall(previous)}

    def restore(match: re.Match) -> str:
        item = match.group(0)
        number = version(item)
        return item if number == build else published.get(number, item)

    text = ITEM.sub(restore, text)
    for delta in sorted(stage.glob("*.delta")):
        match = DELTA.fullmatch(delta.name)
        if not match or match.group(1) != build:
            continue
        name = f"InboxPlus-{build}-{match.group(2)}.delta"
        old_url, new_url = f'url="{prefix}{delta.name}"', f'url="{prefix}{name}"'
        if text.count(old_url) != 1:
            raise ValueError(f"expected one feed reference to {delta.name}")
        text = text.replace(old_url, new_url)
        delta.rename(stage / name)
    feed.write_text(text)


if __name__ == "__main__":
    stage, previous_feed, build, prefix = sys.argv[1:5]
    previous = Path(previous_feed).read_text() if previous_feed else ""
    try:
        finalize(Path(stage), previous, build, prefix)
    except ValueError as error:
        sys.exit(f"error: {error}")
