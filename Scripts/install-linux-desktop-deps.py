#!/usr/bin/env python3
"""Install the Linux desktop packages from the fastest Ubuntu archive mirror."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import time
import urllib.request


PACKAGES = (
    "clang", "cmake", "ninja-build", "pkg-config", "libgtk-3-dev", "libsecret-1-dev",
    "libmpv-dev", "libwebkit2gtk-4.1-dev", "libayatana-appindicator3-dev",
)
MIRRORS = (
    "http://archive.ubuntu.com/ubuntu",
    "http://azure.archive.ubuntu.com/ubuntu",
    "http://us.archive.ubuntu.com/ubuntu",
)
ARCHIVE = re.compile(r"https?://[A-Za-z0-9.-]*archive\.ubuntu\.com/ubuntu/?")


def choose_mirror(samples):
    viable = [(rate, mirror) for mirror, rate in samples if rate and rate > 0]
    if not viable:
        return MIRRORS[0]
    return max(viable)[1]


def rewrite_archive_uris(text, mirror):
    return ARCHIVE.sub(mirror.rstrip("/") + "/", text)


def probe_mirror(mirror, fetch, seconds=3):
    started = time.monotonic()
    try:
        amount = fetch(mirror.rstrip("/") + "/dists/noble/main/binary-amd64/Packages.gz", seconds)
    except Exception:
        return None
    if not amount or amount <= 0:
        return None
    return amount / max(time.monotonic() - started, 0.001)


def restore_debs(cache_dir, archives):
    if not cache_dir.is_dir():
        return 0
    archives.mkdir(parents=True, exist_ok=True)
    copied = 0
    for deb in cache_dir.glob("*.deb"):
        destination = archives / deb.name
        if not destination.exists():
            shutil.copy2(deb, destination)
            copied += 1
    return copied


def store_debs(archives, cache_dir):
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.chmod(0o755)
    stored = 0
    for deb in archives.glob("*.deb"):
        destination = cache_dir / deb.name
        if not destination.exists() or destination.stat().st_size != deb.stat().st_size:
            shutil.copy2(deb, destination)
            stored += 1
        destination.chmod(0o644)
    return stored


def fetch_for(seconds_limit):
    def fetch(url, seconds):
        deadline = time.monotonic() + min(seconds, seconds_limit)
        request = urllib.request.Request(url, headers={"User-Agent": "inboxplus-ci"})
        with urllib.request.urlopen(request, timeout=seconds) as response:
            amount = 0
            while time.monotonic() < deadline:
                chunk = response.read(64 * 1024)
                if not chunk:
                    break
                amount += len(chunk)
            return amount
    return fetch


def install(source_root, archive_dir, apt_archives, mirror, run):
    changed = []
    for path in sorted(source_root.rglob("*")):
        if path.is_file() and (path.suffix == ".sources" or path.name == "sources.list" or path.name.endswith(".list")):
            original = path.read_text()
            rewritten = rewrite_archive_uris(original, mirror)
            if rewritten != original:
                path.write_text(rewritten)
                changed.append(path)
    restore_debs(archive_dir, apt_archives)
    run(["apt-get", "update"])
    run(["apt-get", "install", "-y", "--no-install-recommends", *PACKAGES])
    store_debs(apt_archives, archive_dir)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-dir", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, default=Path("/etc/apt"))
    parser.add_argument("--apt-archives", type=Path, default=Path("/var/cache/apt/archives"))
    arguments = parser.parse_args()
    samples = [(mirror, probe_mirror(mirror, fetch_for(3))) for mirror in MIRRORS]
    mirror = choose_mirror(samples)
    rates = " ".join(f"{url}={(rate or 0):.0f}B/s" for url, rate in samples)
    print(f"linux_packages mirror={mirror} probes={rates}")

    def run(command):
        subprocess.run(command, check=True)

    install(arguments.source_root, arguments.archive_dir, arguments.apt_archives, mirror, run)


if __name__ == "__main__":
    main()
