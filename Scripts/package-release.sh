#!/bin/bash
#
# Builds and signs an Inbox+ release, and notarizes it when signed with an Apple Developer ID.
#
# Every release must be signed with the same certificate. macOS binds permission grants (Full Disk
# Access, Automation) to a code identity, and Sparkle hands each update to the same Mac. An ad-hoc
# signature has no stable identity: its CDHash changes on every build, so each update would look
# like a different application and every grant would have to be given again.
#
# Required environment:
#   INBOXPLUS_RELEASE_SIGNING    self-signed or developer-id
#   INBOXPLUS_SIGNING_IDENTITY   The certificate's name, e.g. "Inbox+ Release Signing" from
#                                Scripts/create-signing-certificate.sh, or
#                                "Developer ID Application: Your Name (TEAMID)"
#   INBOXPLUS_UPDATE_PUBLIC_KEY  Sparkle's public key; see docs/updates.md
#   INBOXPLUS_BUILD_NUMBER       Greater than every shipped build
#
# developer-id also requires:
#   INBOXPLUS_TEAM_ID            Your 10-character Apple team identifier
#   INBOXPLUS_NOTARY_PROFILE     A notarytool keychain profile name, created once with:
#                              xcrun notarytool store-credentials <name> \
#                                --apple-id <you@example.com> --team-id <TEAMID> \
#                                --password <app-specific-password>
#
# self-signed releases are not notarized. Gatekeeper blocks the first launch of a downloaded copy
# until the user chooses Open Anyway in System Settings → Privacy & Security. Sparkle updates
# after that are not blocked.
#
# Usage: Scripts/package-release.sh [output-directory]

set -euo pipefail

OUTPUT_DIR="${1:-build/release}"
APP_NAME="Inbox+"
EXECUTABLE_NAME="InboxPlus"
BUNDLE_ID="com.inboxplus.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() { echo "error: $*" >&2; exit 1; }

REQUIRED=(INBOXPLUS_RELEASE_SIGNING INBOXPLUS_SIGNING_IDENTITY INBOXPLUS_UPDATE_PUBLIC_KEY INBOXPLUS_BUILD_NUMBER)
case "${INBOXPLUS_RELEASE_SIGNING:-}" in
  developer-id) REQUIRED+=(INBOXPLUS_TEAM_ID INBOXPLUS_NOTARY_PROFILE) ;;
  self-signed) ;;
  *) fail "INBOXPLUS_RELEASE_SIGNING must be self-signed or developer-id" ;;
esac
for var in "${REQUIRED[@]}"; do
  [ -n "${!var:-}" ] || fail "$var is not set; see the header of this script"
done
[ "$INBOXPLUS_SIGNING_IDENTITY" != - ] || fail "an ad-hoc signature changes identity on every release"

VERSION="$(grep -o 'current = "[^"]*"' "$REPO_ROOT/Sources/InboxPlusCore/InboxPlusVersion.swift" | cut -d'"' -f2)"
[ -n "$VERSION" ] || fail "could not read the version from Sources/InboxPlusCore/InboxPlusVersion.swift"
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

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$BIN_DIR/InboxPlusRuntimeCLI" "$APP_DIR/Contents/MacOS/InboxPlusRuntimeCLI"
"$REPO_ROOT/Scripts/prepare-bundled-runtime.sh" "$APP_DIR/Contents/Resources/Runtime"
# SwiftPM resource bundles the executable loads through `Bundle.module` — which traps when the
# bundle is absent, so a missing copy here is a crash on launch, not a missing image.
cp -R "$BIN_DIR/InboxPlus_InboxPlusUI.bundle" "$APP_DIR/Contents/Resources/InboxPlus_InboxPlusUI.bundle"

swift "$REPO_ROOT/Scripts/make-icon.swift" "$REPO_ROOT/docs/assets/inboxplus-logo.png" "$REPO_ROOT/Resources/AppIcon.icns"
cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# A real bundle, so the app has a stable identity, a menu bar, and somewhere to declare the
# permission usage strings macOS shows the user.
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Inbox+ uses Automation to send iMessages on your behalf. It is never used for anything else.</string>
  <key>NSContactsUsageDescription</key>
  <string>Inbox+ shows the names from your contacts instead of phone numbers and email addresses in iMessage. Contacts never leave your Mac.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Inbox+ asks for a folder only when you attach a file to a message.</string>
</dict>
</plist>
PLIST

python3 "$REPO_ROOT/Scripts/configure-updates.py" "$APP_DIR" --release

# 2. Sign inner binaries before the bundle. Signing outside-in invalidates the outer signature.
echo "==> Signing ($INBOXPLUS_RELEASE_SIGNING)"
ENTITLEMENTS="$REPO_ROOT/Scripts/inboxplus.entitlements"
HARDENED=""
[ "$INBOXPLUS_RELEASE_SIGNING" = self-signed ] || HARDENED=--hardened
sign_code() {
  if [ -n "$HARDENED" ]; then
    codesign --force --timestamp --options runtime --sign "$INBOXPLUS_SIGNING_IDENTITY" "$@"
  else
    codesign --force --sign "$INBOXPLUS_SIGNING_IDENTITY" "$@"
  fi
}
"$REPO_ROOT/Scripts/sign-bundled-runtime.sh" "$APP_DIR/Contents/Resources/Runtime" "$INBOXPLUS_SIGNING_IDENTITY" $HARDENED
bash "$REPO_ROOT/Scripts/embed-sparkle.sh" "$APP_DIR" "$INBOXPLUS_SIGNING_IDENTITY" $HARDENED
sign_code "$APP_DIR/Contents/MacOS/InboxPlusRuntimeCLI"
sign_code --entitlements "$ENTITLEMENTS" "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
REQUIREMENT="$(codesign -d -r- "$APP_DIR" 2>&1 | sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
  *certificate*) echo "    identity: $REQUIREMENT" ;;
  *) fail "the app's identity is not tied to a certificate: $REQUIREMENT" ;;
esac

ZIP="$REPO_ROOT/$OUTPUT_DIR/InboxPlus-$VERSION-$INBOXPLUS_BUILD_NUMBER.zip"
rm -f "$ZIP"
if [ "$INBOXPLUS_RELEASE_SIGNING" = developer-id ]; then
  # 3. Notarize. Apple must see the bundle before Gatekeeper will run it on someone else's Mac.
  echo "==> Notarizing"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$INBOXPLUS_NOTARY_PROFILE" --wait

  # Stapling attaches the ticket, so the app launches on a Mac that is offline.
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"

  # 4. Re-zip after stapling: the ticket is in the bundle, not in the archive made before it.
  rm -f "$ZIP"
fi
ditto -c -k --keepParent "$APP_DIR" "$ZIP"

# 5. The bill of materials and checksums ship with the release, not after it.
echo "==> Generating release artifacts"
"$APP_DIR/Contents/MacOS/InboxPlusRuntimeCLI" sbom \
  --output "$REPO_ROOT/$OUTPUT_DIR/inboxplus-$VERSION.cdx.json"

INBOXPLUS_RELEASE_VERSION="$VERSION" bash "$REPO_ROOT/Scripts/generate-update-feed.sh" \
  "$REPO_ROOT/$OUTPUT_DIR" "${INBOXPLUS_RELEASE_TAG:-v$VERSION}"

# Earlier releases' ZIPs stay in the directory as delta sources; they are not part of this release.
cd "$REPO_ROOT/$OUTPUT_DIR"
ASSETS=("$(basename "$ZIP")")
for DELTA in InboxPlus-"$INBOXPLUS_BUILD_NUMBER"-*.delta; do
  [ ! -e "$DELTA" ] || ASSETS+=("$DELTA")
done
ASSETS+=("inboxplus-$VERSION.cdx.json" appcast.xml)
shasum -a 256 "${ASSETS[@]}" > SHA256SUMS.txt
ASSETS+=(SHA256SUMS.txt)

echo
echo "==> Done. Upload these from $OUTPUT_DIR to the ${INBOXPLUS_RELEASE_TAG:-v$VERSION} release:"
printf '  %s\n' "${ASSETS[@]}"
echo "Keep $(basename "$ZIP") here: the next release builds its delta update from it."
if [ "$INBOXPLUS_RELEASE_SIGNING" = developer-id ]; then
  echo
  echo "Verify the way a user's Mac will:"
  echo "  spctl --assess --type execute --verbose \"$APP_DIR\""
fi
