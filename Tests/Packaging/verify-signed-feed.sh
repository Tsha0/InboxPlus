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
import os, pathlib, plistlib, shutil, subprocess, sys
import xml.etree.ElementTree as ET
repo, fixture = map(pathlib.Path, sys.argv[1:])
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
    subprocess.run(['bash', str(repo / 'Scripts/generate-update-feed.sh'), str(fixture), f'v{version}'], env=env, check=True)

root = ET.parse(fixture / 'appcast.xml')
enclosures = root.findall('./channel/item/enclosure')
assert len(enclosures) == 2, 'older compatible release was lost'
for item in enclosures:
    url = item.get('url')
    signature = item.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
    archive = fixture / url.rsplit('/', 1)[1]
    subprocess.run([str(repo / '.build/artifacts/sparkle/Sparkle/bin/sign_update'), '--verify',
                    '--ed-key-file', str(fixture / 'private-key'), str(archive), signature], check=True)
assert any('/v0.6.0/' in item.get('url') for item in enclosures)
assert any('/v0.6.1/' in item.get('url') for item in enclosures)
print('Both archive signatures verified; prior release URLs preserved')
PY
