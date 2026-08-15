#!/bin/bash
#
# Builds a double-clickable Pallo.app you can drag into /Applications.
#
#   Scripts/build-app.sh            # ad-hoc signed, for this Mac only
#   Scripts/build-app.sh --install  # ...and copy it into /Applications
#
# This is the local-install path. It does NOT notarize, so the result runs on this Mac and would be
# refused by Gatekeeper on anyone else's. Distributing to other people needs an Apple Developer ID
# and Scripts/package-release.sh.
#
# Set PALLO_SIGNING_IDENTITY to sign with a real or self-signed certificate instead of ad-hoc.
# Worth doing: macOS ties Full Disk Access and Automation grants to a code identity, and an ad-hoc
# signature's identity changes on every build, so every rebuild asks for permission again. A stable
# certificate is what stops that.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pallo"
BUNDLE_ID="com.pallo.app"
BUILD_DIR="$REPO_ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

cd "$REPO_ROOT"

VERSION="$(grep -o 'current = "[^"]*"' Sources/PalloCore/PalloVersion.swift | cut -d'"' -f2)"
[ -n "$VERSION" ] || { echo "error: could not read the version" >&2; exit 1; }

echo "==> Building Pallo $VERSION (release)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Generating the app icon"
swift Scripts/make-icon.swift docs/assets/pallo-mascot.png Resources/AppIcon.icns >/dev/null

echo "==> Assembling the bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
# Shipped alongside so the runtime can be driven without a checkout: the app needs a prepared
# profile, and this is what prepares one.
cp "$BIN_DIR/PalloRuntimeCLI" "$APP_DIR/Contents/MacOS/PalloRuntimeCLI"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles the executable loads through `Bundle.module` — which traps when the
# bundle is absent, so a missing copy here is a crash on launch, not a missing image.
cp -R "$BIN_DIR/Pallo_PalloUI.bundle" "$APP_DIR/Contents/Resources/Pallo_PalloUI.bundle"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key>
  <string>AGPL-3.0-or-later</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Pallo sends your iMessage replies by asking Messages to send them. It is never used for anything else.</string>
</dict>
</plist>
PLIST

# The bundle is a directory, and Finder caches icons aggressively; touching it makes the new icon
# appear without a relaunch of Finder.
touch "$APP_DIR"

echo "==> Signing"
if [ -n "${PALLO_SIGNING_IDENTITY:-}" ]; then
  IDENTITY="$PALLO_SIGNING_IDENTITY"
  echo "    using $IDENTITY"
else
  IDENTITY="-"
  echo "    ad-hoc (permission grants will reset on every rebuild)"
fi

# Inner binaries before the outer bundle: signing outside-in invalidates the outer signature.
codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/PalloRuntimeCLI"
codesign --force --sign "$IDENTITY" \
  --entitlements "$REPO_ROOT/Scripts/pallo.entitlements" \
  "$APP_DIR"
codesign --verify --strict "$APP_DIR"

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  APP_DIR="/Applications/$APP_NAME.app"
fi

echo
echo "Built $APP_DIR"
echo
echo "Next:"
echo "  1. Prepare a profile if you have not already:"
echo "       \"$APP_DIR/Contents/MacOS/PalloRuntimeCLI\" bootstrap --profile demo \\"
echo "         --python /opt/homebrew/opt/python@3.12/bin/python3.12"
echo "  2. Start the runtime and leave it running:"
echo "       \"$APP_DIR/Contents/MacOS/PalloRuntimeCLI\" start --profile demo"
echo "  3. Open Pallo. With exactly one prepared profile it attaches automatically;"
echo "     otherwise set PALLO_PROFILE."
echo
echo "For iMessage, add this exact path to Full Disk Access, then reopen Pallo:"
echo "  $APP_DIR"
