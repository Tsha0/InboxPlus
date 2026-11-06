#!/usr/bin/env python3
"""Build isolated macOS reference and Flutter apps from the shared desktop fixture."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys


root = Path(__file__).resolve().parents[1]
output = root / 'build/desktop-parity'
flutter = os.environ.get('FLUTTER_BINARY', 'flutter')
reference = output / 'Inbox+ reference.app'
comparison = output / 'Inbox+v2 comparison.app'


def run(arguments, **options):
    return subprocess.run(arguments, check=True, **options)


def replace_bundle(path, identifier):
    if not path.exists():
        return
    info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != identifier:
        raise SystemExit(f'Refusing to replace an unrelated app at {path}.')
    shutil.rmtree(path)


if sys.platform != 'darwin':
    raise SystemExit('The Swift desktop reference requires macOS.')
processes = run(['ps', '-axo', 'comm='], capture_output=True, text=True).stdout
if any(str(path / 'Contents/MacOS') in processes for path in [reference, comparison]):
    raise SystemExit('Quit both isolated comparison apps before rebuilding them.')

run(['swift', 'build', '--product', 'InboxPlusDesktopReference'], cwd=root)
binary_directory = Path(run(['swift', 'build', '--show-bin-path'], cwd=root,
                            capture_output=True, text=True).stdout.strip())
run([flutter, 'build', 'macos', '--debug', '--target', 'lib/desktop_preview.dart',
     '--dart-define=INBOXPLUS_APP_NAME=Inbox+v2 comparison',
     f'--dart-define=INBOXPLUS_DESKTOP_FIXTURE={root / "Tests/Fixtures/desktop-parity.json"}'],
    cwd=root / 'apps/inboxplus_flutter')

replace_bundle(reference, 'com.inboxplus.desktop-reference')
(reference / 'Contents/MacOS').mkdir(parents=True)
resources = reference / 'Contents/Resources'
resources.mkdir()
shutil.copy2(binary_directory / 'InboxPlusDesktopReference', reference / 'Contents/MacOS/InboxPlusDesktopReference')
shutil.copytree(binary_directory / 'InboxPlus_InboxPlusUI.bundle', resources / 'InboxPlus_InboxPlusUI.bundle')
shutil.copy2(root / 'Tests/Fixtures/desktop-parity.json', resources / 'desktop-parity.json')
shutil.copy2(root / 'apps/inboxplus_flutter/assets/inboxplus-logo.png', resources / 'inboxplus-logo.png')
(reference / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.inboxplus.desktop-reference',
    'CFBundleName': 'Inbox+ reference', 'CFBundleDisplayName': 'Inbox+ reference',
    'CFBundleExecutable': 'InboxPlusDesktopReference', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.8.5', 'CFBundleVersion': '111',
    'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
}))

replace_bundle(comparison, 'com.inboxplus.desktop-comparison')
run(['ditto', str(root / 'apps/inboxplus_flutter/build/macos/Build/Products/Debug/Inbox+v2.app'), str(comparison)])
info_path = comparison / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info.update(CFBundleIdentifier='com.inboxplus.desktop-comparison',
            CFBundleName='Inbox+v2 comparison', CFBundleDisplayName='Inbox+v2 comparison')
info_path.write_bytes(plistlib.dumps(info))
for app in [reference, comparison]:
    run(['codesign', '--force', '--sign', '-', str(app)])
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    print(app)
