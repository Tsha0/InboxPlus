#!/bin/bash
#
# Builds a double-clickable Inbox+.app you can drag into /Applications.
#
#   Scripts/build-app.sh            # ad-hoc signed, for this Mac only
#   Scripts/build-app.sh --install  # ...and copy it into /Applications
#
# This is the local-install path. It does NOT notarize, so the result runs on this Mac and would be
# refused by Gatekeeper on anyone else's. Distributing to other people needs an Apple Developer ID
# and Scripts/package-release.sh.
#
# Set INBOXPLUS_SIGNING_IDENTITY to sign with a real or self-signed certificate instead of ad-hoc.
# Worth doing: macOS ties Full Disk Access and Automation grants to a code identity, and an ad-hoc
# signature's identity changes on every build, so every rebuild asks for permission again. A stable
# certificate is what stops that.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_NAME="Inbox+"
BUILD_DIR="$REPO_ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

cd "$REPO_ROOT"

VERSION="$(grep -o 'current = "[^"]*"' Sources/InboxPlusCore/InboxPlusVersion.swift | cut -d'"' -f2)"
[ -n "$VERSION" ] || { echo "error: could not read the version" >&2; exit 1; }

echo "==> Building Inbox+ $VERSION (release)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Preparing the bundled messaging runtime"
RUNTIME_DIR="$BUILD_DIR/runtime-bundle"
"$REPO_ROOT/Scripts/prepare-bundled-runtime.sh" "$RUNTIME_DIR" "$BIN_DIR"
echo "==> Assembling the bundle"
bash "$REPO_ROOT/Scripts/assemble-app.sh" "$BIN_DIR" "$APP_DIR" "$VERSION" "$RUNTIME_DIR"

echo "==> Signing"
if [ -n "${INBOXPLUS_SIGNING_IDENTITY:-}" ]; then
  IDENTITY="$INBOXPLUS_SIGNING_IDENTITY"
  echo "    using $IDENTITY"
else
  IDENTITY="-"
  echo "    ad-hoc (permission grants will reset on every rebuild)"
fi

# Inner binaries before the outer bundle: signing outside-in invalidates the outer signature.
"$REPO_ROOT/Scripts/sign-bundled-runtime.sh" "$APP_DIR/Contents/Resources/Runtime" "$IDENTITY"
codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/InboxPlusRuntimeCLI"
codesign --force --sign "$IDENTITY" \
  --entitlements "$REPO_ROOT/Scripts/inboxplus.entitlements" \
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
echo "Open Inbox+. First launch prepares your inbox automatically."
echo
echo "For iMessage, add this exact path to Full Disk Access, then reopen Inbox+:"
echo "  $APP_DIR"
