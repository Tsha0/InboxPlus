#!/usr/bin/env python3
"""Package complete Flutter desktop development builds without publishing them."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps/inboxplus_flutter"
ASSETS = ("third_party_notices.txt", "reaction_emoji.json", "inboxplus-logo.png")
MACH_MAGIC = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def version():
    match = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)\s*$", (APP / "pubspec.yaml").read_text(), re.MULTILINE)
    if match is None:
        raise RuntimeError("The app version must have a version and numeric build number")
    return match.groups()


def default_bundle(target):
    pattern = {
        "macos": "macos/Build/Products/Release/*.app",
        "windows": "windows/x64/runner/Release",
        "linux": "linux/*/release/bundle",
    }[target]
    matches = list((APP / "build").glob(pattern))
    if len(matches) != 1:
        raise RuntimeError("Build one release target first, or select its bundle with --bundle")
    return matches[0]


def check_links(bundle):
    for path in bundle.rglob("*"):
        if not path.is_symlink():
            continue
        destination = path.resolve()
        if not destination.is_relative_to(bundle) or not destination.exists():
            raise RuntimeError("A runtime link points outside the bundle or is broken: " + str(path.relative_to(bundle)))


def layout(target, bundle):
    expected_version, expected_build = version()
    if target == "macos":
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != "com.inboxplus.app":
            raise RuntimeError("The app identity must be com.inboxplus.app, not a comparison fixture")
        if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (expected_version, expected_build):
            raise RuntimeError("The bundle version does not match pubspec.yaml")
        executable = info.get("CFBundleExecutable", "")
        if not executable or Path(executable).name != executable:
            raise RuntimeError("Invalid bundle executable")
        required = ["Contents/MacOS/" + executable, "Contents/Frameworks/libinboxplus_connectors.dylib",
                    "Contents/Frameworks/App.framework/App", "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS"]
        assets = bundle / "Contents/Frameworks/App.framework/Resources/flutter_assets"
        libraries = bundle / "Contents/Frameworks"
        entrypoint = bundle.name
    else:
        assets = bundle / "data/flutter_assets"
        libraries = bundle if target == "windows" else bundle / "lib"
        required = (["InboxPlus.exe", "inboxplus_connectors.dll", "flutter_windows.dll", "data/app.so"]
                    if target == "windows" else
                    ["InboxPlus", "lib/libinboxplus_connectors.so", "lib/libflutter_linux_gtk.so", "lib/libapp.so"])
        entrypoint = required[0]
    for name in required:
        if not (bundle / name).is_file():
            raise RuntimeError("Missing runtime file: " + name)
    binaries = {(bundle / name).resolve() for name in required}
    if (assets / "kernel_blob.bin").exists():
        raise RuntimeError("Debug builds and comparison fixtures cannot be packaged")
    for name in ("AssetManifest.bin", "NativeAssetsManifest.json"):
        if not (assets / name).is_file():
            raise RuntimeError("Missing runtime file: " + name)
    for name in ASSETS:
        if not (assets / "assets" / name).is_file() or (assets / "assets" / name).read_bytes() != (APP / "assets" / name).read_bytes():
            raise RuntimeError("Bundled asset is missing or stale: " + name)
    manifest = json.loads((assets / "NativeAssetsManifest.json").read_text())
    if manifest.get("format-version") != [1, 0, 0] or not manifest.get("native-assets"):
        raise RuntimeError("Unsupported native assets manifest")
    for native_target, entries in manifest["native-assets"].items():
        if not native_target.startswith(target + "_") or "package:sqlite3/src/ffi/libsqlite3.g.dart" not in entries:
            raise RuntimeError("Encrypted SQLite native asset is missing for the target")
        for descriptor in entries.values():
            if not isinstance(descriptor, list) or len(descriptor) != 2 or descriptor[0] != "absolute":
                raise RuntimeError("Unsupported native asset location")
            path = PurePosixPath(descriptor[1])
            if path.is_absolute() or PureWindowsPath(path).drive or ".." in path.parts or "\\" in descriptor[1]:
                raise RuntimeError("Native asset is not relocatable")
            if not (libraries / path).is_file():
                raise RuntimeError("Missing runtime file: " + descriptor[1])
            binaries.add((libraries / path).resolve())
    return bundle / required[0], entrypoint, set(manifest["native-assets"]), binaries


def binary_architectures(target, path, *, allow_elf=False):
    with path.open("rb") as source:
        header = source.read(64)
        if (target == "linux" or allow_elf) and len(header) == 64 and header[:6] == b"\x7fELF\x02\x01":
            machine = struct.unpack_from("<H", header, 18)[0]
            if machine in (62, 183):
                return {"x64" if machine == 62 else "arm64"}
        if target == "windows" and len(header) == 64 and header[:2] == b"MZ":
            source.seek(struct.unpack_from("<I", header, 60)[0])
            signature = source.read(6)
            if signature == b"PE\0\0\x64\x86":
                return {"x64"}
    if target == "macos" and header[:4] in MACH_MAGIC:
        result = subprocess.run(["lipo", "-archs", str(path)], capture_output=True, text=True, check=True)
        architectures = set(result.stdout.split())
        if architectures and architectures <= {"x86_64", "arm64"}:
            return {"x64" if value == "x86_64" else value for value in architectures}
    raise RuntimeError("Unsupported binary architecture: " + path.name)


def verify_bundle(target, bundle):
    executable, entrypoint, native_targets, binaries = layout(target, bundle)
    check_links(bundle)
    if target == "macos":
        if sys.platform != "darwin":
            raise RuntimeError("macOS signature verification requires a Mac")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    if target != "windows" and not executable.stat().st_mode & 0o111:
        raise RuntimeError("The bundle executable has lost its execute permission")
    architectures = binary_architectures(target, executable)
    if native_targets != {target + "_" + value for value in architectures}:
        raise RuntimeError("Native asset architecture does not match the executable")
    checked = set()
    for path in bundle.rglob("*"):
        if not path.is_file() or path.resolve() in checked:
            continue
        checked.add(path.resolve())
        with path.open("rb") as source:
            magic = source.read(4)
        native = (path.resolve() in binaries or
                  target == "macos" and magic in MACH_MAGIC or
                  target == "linux" and magic == b"\x7fELF" or
                  target == "windows" and path.suffix.lower() in (".exe", ".dll", ".so"))
        if native and not architectures <= binary_architectures(
                target, path, allow_elf=target == "windows" and path == bundle / "data/app.so"):
            raise RuntimeError("Runtime architecture does not match: " + str(path.relative_to(bundle)))
    return sorted(architectures), entrypoint


def write_archive(target, container, destination):
    if target == "macos":
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(container), str(destination)], check=True)
    elif target == "windows":
        with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(container.rglob("*")):
                archive.write(path, path.relative_to(container.parent).as_posix())
    else:
        def anonymous(info):
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            return info
        with tarfile.open(destination, "w:gz") as archive:
            archive.add(container, arcname=container.name, filter=anonymous)


def package(target, bundle, output):
    bundle = Path(bundle).resolve(strict=True)
    output = Path(output).resolve()
    if output.is_relative_to(bundle):
        raise RuntimeError("The output directory cannot be inside the runtime bundle")
    architectures, entrypoint = verify_bundle(target, bundle)
    app_version, build = version()
    architecture = "universal" if len(architectures) > 1 else architectures[0]
    extension = ".tar.gz" if target == "linux" else ".zip"
    filename = "InboxPlus-" + app_version + "+" + build + "-" + target + "-" + architecture + "-dev" + extension
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".inboxplus-package-", dir=output) as temporary:
        staging = Path(temporary)
        container = staging / "Inbox+v2"
        container.mkdir()
        if target == "macos":
            staged_bundle = container / bundle.name
            subprocess.run(["ditto", str(bundle), str(staged_bundle)], check=True)
        else:
            staged_bundle = container
            shutil.copytree(bundle, container, dirs_exist_ok=True, symlinks=target != "windows")
        architectures, entrypoint = verify_bundle(target, staged_bundle)
        shutil.copy2(ROOT / "LICENSE", container / "LICENSE")
        shutil.copy2(ROOT / "docs/sbom.cdx.json", container / "sbom.cdx.json")
        (container / "build-info.json").write_text(json.dumps({
            "format_version": 1, "development": True, "version": app_version, "build": build,
            "target": target, "architectures": architectures, "entrypoint": entrypoint,
        }, indent=2) + "\n")
        archive = staging / filename
        write_archive(target, container, archive)
        checksum = staging / (filename + ".sha256")
        digest = hashlib.sha256()
        with archive.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        checksum.write_text(digest.hexdigest() + "  " + filename + "\n")
        os.replace(archive, output / filename)
        os.replace(checksum, output / checksum.name)
    return output / filename


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, choices=("macos", "windows", "linux"))
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "build/flutter-desktop")
    arguments = parser.parse_args()
    try:
        print(package(arguments.target, arguments.bundle or default_bundle(arguments.target), arguments.output))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
