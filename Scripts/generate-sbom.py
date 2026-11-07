#!/usr/bin/env python3
"""Generate the repository inventory from pub and Go dependency pins."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import uuid
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[1]


def licensed(component, reviews, key):
    review = reviews[key]
    expression = review["license"]
    if " AND " in expression or " OR " in expression:
        component["licenses"] = [{"expression": expression}]
    else:
        component["licenses"] = [{"license": {"id": expression}}]
    if review.get("note"):
        component["description"] = review["note"]
    return component


def pub_components(reviews):
    components = {}
    for lock in ("apps/inboxplus_flutter/pubspec.lock", "packages/inboxplus_storage/pubspec.lock"):
        content = (ROOT / lock).read_text()
        blocks = re.findall(r"^  (\w+):\n(.*?)(?=^  \w+:\n|^sdks:|\Z)", content, re.M | re.S)
        for name, block in blocks:
            source = re.search(r"^    source: (\w+)$", block, re.M).group(1)
            if source in ("sdk", "path"):
                continue
            if source != "hosted" or 'url: "https://pub.dev"' not in block:
                raise ValueError("Unreviewed pub dependency source: " + name)
            version = re.search(r'^    version: "([^"]+)"$', block, re.M).group(1)
            checksum = re.search(r'^      sha256: "?([a-f0-9]{64})"?$', block, re.M).group(1)
            purl = "pkg:pub/" + name + "@" + quote(version, safe="")
            component = {
                "type": "library", "name": name, "version": version, "purl": purl,
                "hashes": [{"alg": "SHA-256", "content": checksum}],
                "externalReferences": [{"type": "distribution", "url": "https://pub.dev/packages/" + name + "/versions/" + version}],
            }
            licensed(component, reviews, "pub:" + name + "@" + version)
            previous = components.get(purl)
            if previous is not None and previous != component:
                raise ValueError("Conflicting pub lock records: " + name)
            components[purl] = component
    return list(components.values())


def go_components(reviews):
    content = (ROOT / "native/connectors/go.mod").read_text()
    requirements = []
    for block in re.findall(r"^require \(\n(.*?)^\)", content, re.M | re.S):
        requirements.extend(re.findall(r"^\s+(\S+)\s+(v\S+)", block, re.M))
    replacements = dict(
        (original, (replacement, version))
        for original, replacement, version in re.findall(r"^replace (\S+) => (\S+) (v\S+)$", content, re.M)
    )
    checksums = {}
    for line in (ROOT / "native/connectors/go.sum").read_text().splitlines():
        name, version, checksum = line.split()
        checksums[name + "@" + version] = checksum
    components = []
    for original, version in requirements:
        name, version = replacements.get(original, (original, version))
        checksum = checksums[name + "@" + version]
        component = {
            "type": "library", "name": name, "version": version,
            "purl": "pkg:golang/" + name + "@" + version,
            "externalReferences": [{"type": "distribution", "url": "https://pkg.go.dev/" + name + "@" + version}],
            "properties": [{"name": "inboxplus:go:module-content-checksum", "value": checksum}],
        }
        if original != name:
            component["properties"].append({"name": "inboxplus:go:replaces", "value": original})
        components.append(licensed(component, reviews, "golang:" + name + "@" + version))
    return components


def generate():
    reviews = json.loads((ROOT / "docs/dependency-licenses.json").read_text())
    application_version = re.search(r"^version: (\S+)$", (ROOT / "apps/inboxplus_flutter/pubspec.yaml").read_text(), re.M).group(1)
    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application", "name": "Inbox+", "version": application_version,
                "licenses": [{"license": {"id": "AGPL-3.0-or-later"}}],
            },
            "properties": [{
                "name": "inboxplus:inventory-scope",
                "value": "Repository inventory: Flutter app and build tools, embedded connectors. Not every component is distributed in every app.",
            }],
        },
        "components": pub_components(reviews) + go_components(reviews),
    }
    for name, version, source, license_id in (
        ("Flutter", "3.47.9", "https://github.com/flutter/flutter/tree/3.47.9", "BSD-3-Clause"),
        ("Dart", "3.13.7", "https://github.com/dart-lang/sdk/tree/3.13.7", "BSD-3-Clause"),
        ("Go", "1.27.3", "https://go.dev/dl/#go1.27.3", "BSD-3-Clause"),
        ("Pillow", "10.4.0", "https://github.com/python-pillow/Pillow/tree/10.4.0", "HPND"),
    ):
        document["components"].append({
            "type": "framework" if name == "Flutter" else "application",
            "name": name, "version": version,
            "purl": "pkg:generic/" + name.lower() + "@" + version,
            "licenses": [{"license": {"id": license_id}}],
            "externalReferences": [{"type": "vcs", "url": source}],
            "properties": [{"name": "inboxplus:usage", "value": "build-toolchain"}],
        })
    document["components"].sort(key=lambda component: (component["name"], component["version"]))
    payload = json.dumps({"components": document["components"], "version": application_version}, sort_keys=True).encode()
    digest = hashlib.sha256(payload).digest()[:16]
    document["serialNumber"] = "urn:uuid:" + str(uuid.UUID(bytes=digest, version=4))
    return json.dumps(document, indent=2, sort_keys=True) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/sbom.cdx.json")
    arguments = parser.parse_args()
    arguments.output.write_text(generate())
