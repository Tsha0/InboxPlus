#!/bin/bash
# Real Sparkle tooling, disposable signing key and fixture apps. No Keychain or publication.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
FIXTURE="$(mktemp -d /private/tmp/inboxplus-signed-feed.XXXXXX)"
trap 'rm -rf "$FIXTURE"' EXIT
cat > "$FIXTURE/key.swift" <<'SWIFT'
import Foundation
import CryptoKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let privateURL = directory.appendingPathComponent("private-key")
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: privateURL)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to: directory.appendingPathComponent("public-key"))
SWIFT
swift "$FIXTURE/key.swift" "$FIXTURE"
python3 - "$REPO_ROOT" "$FIXTURE" <<'PY'
import os, pathlib, plistlib, re, shutil, subprocess, sys
import xml.etree.ElementTree as ET
repo, fixture = map(pathlib.Path, sys.argv[1:])
tools = repo / '.build/artifacts/sparkle/Sparkle/bin'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
(fixture / 'notes.html').write_text('<p>First release notes</p>')
published = None
app = fixture / 'Inbox+.app'
(app / 'Contents/MacOS').mkdir(parents=True)
shutil.copyfile('/usr/bin/true', app / 'Contents/MacOS/InboxPlus')
os.chmod(str(app / 'Contents/MacOS/InboxPlus'), 0o755)
for version, build in [('0.6.0', '106'), ('0.6.1', '107')]:
    info = {'CFBundleIdentifier': 'com.inboxplus.update-test', 'CFBundleName': 'Inbox+',
            'CFBundleExecutable': 'InboxPlus', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': build, 'CFBundleShortVersionString': version,
            'LSMinimumSystemVersion': '15.0', 'SUFeedURL': 'https://example.com/appcast.xml',
            'SUPublicEDKey': (fixture / 'public-key').read_text()}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    archive = fixture / f'InboxPlus-{version}-{build}.zip'
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
    env = dict(os.environ, INBOXPLUS_RELEASE_VERSION=version, INBOXPLUS_BUILD_NUMBER=build,
               INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE=str(fixture / 'private-key'))
    if build == '106':
        env['INBOXPLUS_RELEASE_NOTES_FILE'] = str(fixture / 'notes.html')
    subprocess.run(['bash', str(repo / 'Scripts/generate-update-feed.sh'), str(fixture), f'v{version}'], env=env, check=True)
    if published is None:
        published = re.search(r'<item>.*?</item>', (fixture / 'appcast.xml').read_text(), re.DOTALL).group(0)

root = ET.parse(fixture / 'appcast.xml')
enclosures = root.findall('./channel/item/enclosure')
assert len(enclosures) == 2, 'older compatible release was lost'
for item in enclosures:
    url = item.get('url')
    signature = item.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
    archive = fixture / url.rsplit('/', 1)[1]
    subprocess.run([str(tools / 'sign_update'), '--verify',
                    '--ed-key-file', str(fixture / 'private-key'), str(archive), signature], check=True)
assert any('/v0.6.0/' in item.get('url') for item in enclosures)
assert any('/v0.6.1/' in item.get('url') for item in enclosures)
assert published in (fixture / 'appcast.xml').read_text(), 'the published 0.6.0 entry was rewritten'
assert 'First release notes' in published

deltas = root.findall('./channel/item/' + SPARKLE + 'deltas/enclosure')
assert len(deltas) == 1, 'expected one delta update, from 0.6.0'
delta = deltas[0]
assert delta.get('url') == 'https://github.com/Tsha0/InboxPlus/releases/download/v0.6.1/InboxPlus-107-106.delta'
assert delta.get(SPARKLE + 'deltaFrom') == '106'
patch = fixture / 'InboxPlus-107-106.delta'
subprocess.run([str(tools / 'sign_update'), '--verify', '--ed-key-file', str(fixture / 'private-key'),
                str(patch), delta.get(SPARKLE + 'edSignature')], check=True)

def cdhash(path):
    out = subprocess.run(['codesign', '-dvvv', str(path)], capture_output=True, text=True).stderr
    return re.search(r'^CDHash=(\w+)', out, re.MULTILINE).group(1)

for version, build in [('0.6.0', '106'), ('0.6.1', '107')]:
    subprocess.run(['ditto', '-x', '-k', str(fixture / f'InboxPlus-{version}-{build}.zip'), str(fixture / build)], check=True)
subprocess.run([str(tools / 'BinaryDelta'), 'apply', str(fixture / '106/Inbox+.app'),
                str(fixture / 'patched.app'), str(patch)], check=True, capture_output=True)
assert cdhash(fixture / 'patched.app') == cdhash(fixture / '107/Inbox+.app'), 'delta did not reproduce 0.6.1'
print('Archive and delta signatures verified; the delta rebuilds 0.6.1; the 0.6.0 entry is unchanged')
PY
