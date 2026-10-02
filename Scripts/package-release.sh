#!/bin/bash
#
# Builds, signs, notarizes and staples an Inbox+ release.
#
# Nothing here can run without an Apple Developer ID. That is not a limitation of the script — it
# is the point: macOS binds permission grants (Full Disk Access, Automation, Screen Recording) to
# a code identity, and an ad-hoc signature has no stable identity. Its CDHash changes on every
# build, so every rebuild looks like a different application and every grant has to be given again.
# That is why development builds re-prompt for permission constantly.
#
# Required environment:
#   INBOXPLUS_SIGNING_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   INBOXPLUS_TEAM_ID            Your 10-character Apple team identifier
#   INBOXPLUS_NOTARY_PROFILE     A notarytool keychain profile name, created once with:
#                              xcrun notarytool store-credentials <name> \
#                                --apple-id <you@example.com> --team-id <TEAMID> \
#                                --password <app-specific-password>
#
# Usage: Scripts/package-release.sh [output-directory]

set -euo pipefail

OUTPUT_DIR="${1:-build/release}"
APP_NAME="Inbox+"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() { echo "error: $*" >&2; exit 1; }

for var in INBOXPLUS_SIGNING_IDENTITY INBOXPLUS_TEAM_ID INBOXPLUS_NOTARY_PROFILE; do
  [ -n "${!var:-}" ] || fail "$var is not set; see the header of this script"
done

VERSION="$(grep -o 'current = "[^"]*"' "$REPO_ROOT/Sources/InboxPlusCore/InboxPlusVersion.swift" | cut -d'"' -f2)"
[ -n "$VERSION" ] || fail "could not read the version from Sources/InboxPlusCore/InboxPlusVersion.swift"
echo "==> Packaging $APP_NAME $VERSION"

# 1. Test before building anything shippable. A release that was never green is not a release.
echo "==> Running tests"
(cd "$REPO_ROOT" && swift test --no-parallel)

echo "==> Building release binaries"
(cd "$REPO_ROOT" && swift build -c release)

BIN_DIR="$(cd "$REPO_ROOT" && swift build -c release --show-bin-path)"
APP_DIR="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
RUNTIME_DIR="$REPO_ROOT/build/runtime-bundle"
"$REPO_ROOT/Scripts/prepare-bundled-runtime.sh" "$RUNTIME_DIR" "$BIN_DIR"
bash "$REPO_ROOT/Scripts/assemble-app.sh" "$BIN_DIR" "$APP_DIR" "$VERSION" "$RUNTIME_DIR"

# 2. Sign inner binaries before the bundle. Signing outside-in invalidates the outer signature.
echo "==> Signing"
ENTITLEMENTS="$REPO_ROOT/Scripts/inboxplus.entitlements"
"$REPO_ROOT/Scripts/sign-bundled-runtime.sh" "$APP_DIR/Contents/Resources/Runtime" "$INBOXPLUS_SIGNING_IDENTITY"
codesign --force --timestamp --options runtime \
  --sign "$INBOXPLUS_SIGNING_IDENTITY" \
  "$APP_DIR/Contents/MacOS/InboxPlusRuntimeCLI"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$INBOXPLUS_SIGNING_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# 3. Notarize. Apple must see the bundle before Gatekeeper will run it on someone else's Mac.
echo "==> Notarizing"
ZIP="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$INBOXPLUS_NOTARY_PROFILE" --wait

# Stapling attaches the ticket, so the app launches on a Mac that is offline.
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

# 4. Re-zip after stapling: the ticket is in the bundle, not in the archive made before it.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"

# 5. The bill of materials and checksums ship with the release, not after it.
echo "==> Generating release artifacts"
"$APP_DIR/Contents/MacOS/InboxPlusRuntimeCLI" sbom \
  --output "$REPO_ROOT/$OUTPUT_DIR/inboxplus-$VERSION.cdx.json"

(cd "$REPO_ROOT/$OUTPUT_DIR" && shasum -a 256 ./*.zip ./*.cdx.json > "SHA256SUMS.txt")

echo
echo "==> Done. Artifacts in $OUTPUT_DIR:"
ls -1 "$REPO_ROOT/$OUTPUT_DIR"
echo
echo "Verify the way a user's Mac will:"
echo "  spctl --assess --type execute --verbose \"$APP_DIR\""
