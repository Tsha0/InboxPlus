#!/bin/bash
# Generate signed metadata pointing to immutable assets on a specific GitHub Release.
# The private key comes from Sparkle's Keychain entry or INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE.
# Earlier release ZIPs left in the release directory become small delta updates from those builds.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RELEASE_DIR="${1:?release artifact directory required}"
TAG="${2:?GitHub release tag required}"
TOOLS="$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin"
STAGE="$(mktemp -d "$RELEASE_DIR/.appcast.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

ZIP="$RELEASE_DIR/InboxPlus-${INBOXPLUS_RELEASE_VERSION:?}-${INBOXPLUS_BUILD_NUMBER:?}.zip"
cp "$ZIP" "$STAGE/"
for EARLIER in "$RELEASE_DIR"/InboxPlus-*.zip; do
  [ "$EARLIER" = "$ZIP" ] || ln "$EARLIER" "$STAGE/"
done
PUBLISHED=""
if [ -f "$RELEASE_DIR/appcast.xml" ]; then
  cp "$RELEASE_DIR/appcast.xml" "$STAGE/appcast.xml"
  PUBLISHED="$RELEASE_DIR/appcast.xml"
fi
if [ -n "${INBOXPLUS_RELEASE_NOTES_FILE:-}" ]; then
  cp "$INBOXPLUS_RELEASE_NOTES_FILE" "$STAGE/$(basename "$ZIP" .zip).html"
fi

KEY_ARGS=()
if [ -n "${INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
  KEY_ARGS=(--ed-key-file "$INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE")
fi
ENCODED_TAG="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")"
PREFIX="https://github.com/Tsha0/InboxPlus/releases/download/$ENCODED_TAG/"
"$TOOLS/generate_appcast" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
  --download-url-prefix "$PREFIX" \
  --maximum-deltas 3 --versions "$INBOXPLUS_BUILD_NUMBER" --embed-release-notes "$STAGE"
test -s "$STAGE/appcast.xml"
python3 "$REPO_ROOT/Scripts/finalize-update-feed.py" "$STAGE" "$PUBLISHED" "$INBOXPLUS_BUILD_NUMBER" "$PREFIX"
python3 "$REPO_ROOT/Scripts/validate-update-feed.py" "$STAGE/appcast.xml" Tsha0/InboxPlus "$TAG" "$INBOXPLUS_BUILD_NUMBER"
for DELTA in "$STAGE"/InboxPlus-"$INBOXPLUS_BUILD_NUMBER"-*.delta; do
  [ ! -e "$DELTA" ] || cp "$DELTA" "$RELEASE_DIR/"
done
cp "$STAGE/appcast.xml" "$RELEASE_DIR/appcast.xml"
