#!/bin/bash
#
# Builds, signs, notarizes and staples a Pallo release.
#
# Nothing here can run without an Apple Developer ID. That is not a limitation of the script — it
# is the point: macOS binds permission grants (Full Disk Access, Automation, Screen Recording) to
# a code identity, and an ad-hoc signature has no stable identity. Its CDHash changes on every
# build, so every rebuild looks like a different application and every grant has to be given again.
# That is why development builds re-prompt for permission constantly.
#
# Required environment:
#   PALLO_SIGNING_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   PALLO_TEAM_ID            Your 10-character Apple team identifier
#   PALLO_NOTARY_PROFILE     A notarytool keychain profile name, created once with:
#                              xcrun notarytool store-credentials <name> \
#                                --apple-id <you@example.com> --team-id <TEAMID> \
#                                --password <app-specific-password>
#
# Usage: Scripts/package-release.sh [output-directory]

set -euo pipefail

OUTPUT_DIR="${1:-build/release}"
APP_NAME="Pallo"
BUNDLE_ID="com.pallo.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "error: $*" >&2; exit 1; }

for var in PALLO_SIGNING_IDENTITY PALLO_TEAM_ID PALLO_NOTARY_PROFILE; do
  [ -n "${!var:-}" ] || fail "$var is not set; see the header of this script"
done

VERSION="$(grep -o 'current = "[^"]*"' "$REPO_ROOT/Sources/PalloCore/PalloVersion.swift" | cut -d'"' -f2)"
[ -n "$VERSION" ] || fail "could not read the version from Sources/PalloCore/PalloVersion.swift"
echo "==> Packaging $APP_NAME $VERSION"

# 1. Test before building anything shippable. A release that was never green is not a release.
echo "==> Running tests"
(cd "$REPO_ROOT" && swift test)

echo "==> Building release binaries"
(cd "$REPO_ROOT" && swift build -c release)

BIN_DIR="$(cd "$REPO_ROOT" && swift build -c release --show-bin-path)"
APP_DIR="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/PalloRuntimeCLI" "$APP_DIR/Contents/MacOS/PalloRuntimeCLI"
# SwiftPM resource bundles the executable loads through `Bundle.module` — which traps when the
# bundle is absent, so a missing copy here is a crash on launch, not a missing image.
cp -R "$BIN_DIR/Pallo_PalloUI.bundle" "$APP_DIR/Contents/Resources/Pallo_PalloUI.bundle"

# A real bundle, so the app has a stable identity, a menu bar, and somewhere to declare the
# permission usage strings macOS shows the user.
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Pallo uses Automation to send iMessages on your behalf. It is never used for anything else.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Pallo asks for a folder only when you attach a file to a message.</string>
</dict>
</plist>
PLIST

# 2. Sign inner binaries before the bundle. Signing outside-in invalidates the outer signature.
echo "==> Signing"
ENTITLEMENTS="$REPO_ROOT/Scripts/pallo.entitlements"
codesign --force --timestamp --options runtime \
  --sign "$PALLO_SIGNING_IDENTITY" \
  "$APP_DIR/Contents/MacOS/PalloRuntimeCLI"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$PALLO_SIGNING_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# 3. Notarize. Apple must see the bundle before Gatekeeper will run it on someone else's Mac.
echo "==> Notarizing"
ZIP="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PALLO_NOTARY_PROFILE" --wait

# Stapling attaches the ticket, so the app launches on a Mac that is offline.
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

# 4. Re-zip after stapling: the ticket is in the bundle, not in the archive made before it.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"

# 5. The bill of materials and checksums ship with the release, not after it.
echo "==> Generating release artifacts"
"$APP_DIR/Contents/MacOS/PalloRuntimeCLI" sbom \
  --output "$REPO_ROOT/$OUTPUT_DIR/pallo-$VERSION.cdx.json"

(cd "$REPO_ROOT/$OUTPUT_DIR" && shasum -a 256 ./*.zip ./*.cdx.json > "SHA256SUMS.txt")

echo
echo "==> Done. Artifacts in $OUTPUT_DIR:"
ls -1 "$REPO_ROOT/$OUTPUT_DIR"
echo
echo "Verify the way a user's Mac will:"
echo "  spctl --assess --type execute --verbose \"$APP_DIR\""
