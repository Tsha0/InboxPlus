#!/usr/bin/env python3
"""Reuse a locally built macOS connector only for identical verified inputs."""

import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(go):
    settings = json.loads(subprocess.check_output([
        go, "env", "-json", "GOVERSION", "GOOS", "GOARCH", "GOAMD64", "GOARM64",
        "CGO_ENABLED", "CGO_CFLAGS", "CGO_CPPFLAGS", "CGO_CXXFLAGS", "CGO_LDFLAGS",
        "CC", "CXX", "PKG_CONFIG", "GOEXPERIMENT", "GOFLAGS", "GOWORK",
    ], text=True))
    compiler = subprocess.check_output(shlex.split(settings["CC"]) + ["--version"], text=True)
    cxx = subprocess.check_output(shlex.split(settings["CXX"]) + ["--version"], text=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-build-version"], text=True)
    packages = subprocess.check_output([go, "list", "-deps", "-json", "."], text=True)
    decoder = json.JSONDecoder()
    files = {}
    while packages.strip():
        package, offset = decoder.raw_decode(packages.lstrip())
        packages = packages.lstrip()[offset:]
        for field in ("GoFiles", "CgoFiles", "CFiles", "CXXFiles", "MFiles", "HFiles",
                      "FFiles", "SFiles", "SwigFiles", "SwigCXXFiles", "SysoFiles", "EmbedFiles"):
            for name in package.get(field, []):
                path = Path(package["Dir"]) / name
                files[str(path)] = digest(path)
    for name in ("go.mod", "go.sum", "build.sh"):
        files[name] = digest(Path(name))
    environment = {key: os.environ.get(key, "") for key in (
        "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "CPATH",
        "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "PKG_CONFIG_PATH",
    )}
    inputs = {"settings": settings, "compiler": compiler, "cxx": cxx, "sdk": sdk, "files": files,
              "environment": environment, "builder": digest(Path(__file__)),
              "mode": "c-shared", "trimpath": True, "cache_version": 1}
    key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    return key, settings


def build(go, output, cache):
    started = time.monotonic()
    key, settings = fingerprint(go)
    entry = Path(cache) / key
    library = entry / "libinboxplus_connectors.dylib"
    header = library.with_suffix(".h")
    record = entry / "sha256.json"
    hit = False
    if record.is_file() and library.is_file() and header.is_file():
        expected = json.loads(record.read_text())
        hit = expected == {"library": digest(library), "header": digest(header)}
    if not hit:
        entry.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=entry) as temporary:
            built = Path(temporary) / library.name
            subprocess.run([go, "build", "-trimpath", "-buildmode=c-shared", "-o", str(built), "."], check=True)
            shutil.copy2(built, library)
            shutil.copy2(built.with_suffix(".h"), header)
            record.write_text(json.dumps({"library": digest(library), "header": digest(header)}))
    shutil.copy2(library, output)
    shutil.copy2(header, Path(output).with_suffix(".h"))
    print(f"connector_build arch={settings['GOARCH']} cache={'hit' if hit else 'miss'} "
          f"seconds={time.monotonic() - started:.3f}", flush=True)


if __name__ == "__main__":
    build(*sys.argv[1:])
