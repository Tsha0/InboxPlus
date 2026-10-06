#!/bin/bash
# Copy the exact SwiftPM binary artifact with its symlinks and sign helpers inside-out.
set -euo pipefail
APP_DIR="${1:?app bundle required}"
IDENTITY="${2:--}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$REPO_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SOURCE" ] || { echo 'error: resolve the pinned Sparkle Swift package first' >&2; exit 1; }
mkdir -p "$APP_DIR/Contents/Frameworks"
FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
ditto "$SOURCE" "$FRAMEWORK"
mkdir -p "$APP_DIR/Contents/Resources/ThirdPartyNotices"
cp "$REPO_ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP_DIR/Contents/Resources/ThirdPartyNotices/Sparkle.txt"

sign() {
  if [ "$IDENTITY" = - ]; then
    codesign --force --sign "$IDENTITY" "$1"
  else
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$1"
  fi
}

VERSION="$FRAMEWORK/Versions/B"
sign "$VERSION/Autoupdate"
sign "$VERSION/Updater.app"
sign "$VERSION/XPCServices/Downloader.xpc"
sign "$VERSION/XPCServices/Installer.xpc"
sign "$FRAMEWORK"
codesign --verify --deep --strict "$FRAMEWORK"
