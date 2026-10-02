#!/bin/bash
# Shared bundle assembly for local installs and notarized releases.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${1:?usage: assemble-app.sh binary-directory output/Inbox+.app version runtime-directory}"
APP_DIR="${2:?missing app directory}"
VERSION="${3:?missing version}"
RUNTIME_DIR="${4:?missing prepared runtime directory}"
case "$APP_DIR" in
  */Inbox+.app) ;;
  *) echo "error: bundle destination must end in /Inbox+.app" >&2; exit 1 ;;
esac

# Fail before replacing an existing bundle when any required input is missing.
for input in "$BIN_DIR/InboxPlus" "$BIN_DIR/InboxPlusRuntimeCLI" "$BIN_DIR/InboxPlus_InboxPlusUI.bundle" \
  "$REPO_ROOT/Resources/AppIcon.icns" "$RUNTIME_DIR/Synapse/runtime-manifest.json" \
  "$RUNTIME_DIR/Synapse/requirements.lock" "$RUNTIME_DIR/Python/bin/python3.12" \
  "$RUNTIME_DIR/libolm.3.dylib"; do
  [ -e "$input" ] || { echo "error: missing bundle input: $input" >&2; exit 1; }
done
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/InboxPlus" "$BIN_DIR/InboxPlusRuntimeCLI" "$APP_DIR/Contents/MacOS/"
cp -R "$BIN_DIR/InboxPlus_InboxPlusUI.bundle" "$APP_DIR/Contents/Resources/"
cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
cp -R "$RUNTIME_DIR" "$APP_DIR/Contents/Resources/Runtime"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>InboxPlus</string>
  <key>CFBundleIdentifier</key><string>com.inboxplus.app</string>
  <key>CFBundleName</key><string>Inbox+</string>
  <key>CFBundleDisplayName</key><string>Inbox+</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>AGPL-3.0-or-later</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Inbox+ sends your iMessage replies by asking Messages to send them.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Inbox+ asks for a folder only when you attach a file to a message.</string>
</dict>
</plist>
touch "$APP_DIR"
