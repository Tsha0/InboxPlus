#!/bin/bash
# A self-signed release keeps one code identity across builds, so macOS permission grants survive
# Sparkle updates. Uses a disposable keychain, added to the search list only while this runs
# because codesign finds identities nowhere else.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
FIXTURE="$(mktemp -d /private/tmp/inboxplus-self-signed.XXXXXX)"
KEYCHAIN="$FIXTURE/signing.keychain-db"
ORIGINAL_KEYCHAINS=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line#\"}"; ORIGINAL_KEYCHAINS+=("${line%\"}")
done < <(security list-keychains -d user)
cleanup() {
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

security create-keychain -p fixture "$KEYCHAIN"
security unlock-keychain -p fixture "$KEYCHAIN"
security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"

NAME="Inbox+ Test Signing $$"
export INBOXPLUS_CERTIFICATE_NAME="$NAME" INBOXPLUS_CERTIFICATE_PASSWORD=fixture-backup
bash "$REPO_ROOT/Scripts/create-signing-certificate.sh" "$FIXTURE/backup.p12" "$KEYCHAIN" >/dev/null
test -s "$FIXTURE/backup.p12"
if bash "$REPO_ROOT/Scripts/create-signing-certificate.sh" "$FIXTURE/second.p12" "$KEYCHAIN" 2>/dev/null; then
  echo 'a second certificate with the same name was created' >&2; exit 1
fi
# Lets codesign use the key without a Keychain prompt, which would hang a headless run.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k fixture "$KEYCHAIN" >/dev/null

build() {
  local app="$FIXTURE/$1/Inbox+.app" executable="$2" identity="$3"
  mkdir -p "$app/Contents/MacOS"
  cp "$executable" "$app/Contents/MacOS/InboxPlus"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.inboxplus.app' \
    -c 'Add :CFBundleExecutable string InboxPlus' -c 'Add :CFBundlePackageType string APPL' \
    "$app/Contents/Info.plist" >/dev/null
  bash "$REPO_ROOT/Scripts/embed-sparkle.sh" "$app" "$identity" 2>/dev/null
  codesign --force --sign "$identity" --entitlements "$REPO_ROOT/Scripts/inboxplus.entitlements" "$app" 2>/dev/null
  codesign --verify --deep --strict "$app"
  echo "$app"
}

FIRST="$(build first /usr/bin/true "$NAME")"
REQUIREMENT="$(codesign -d -r- "$FIRST" 2>&1 | sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
  'identifier "com.inboxplus.app" and certificate leaf = H"'*) ;;
  *) echo "identity is not pinned to the certificate: $REQUIREMENT" >&2; exit 1 ;;
esac

UPDATE="$(build update /usr/bin/false "$NAME")"
codesign --verify --deep --strict -R="$REQUIREMENT" "$UPDATE"

ADHOC="$(build adhoc /usr/bin/false -)"
if codesign --verify -R="$REQUIREMENT" "$ADHOC" 2>/dev/null; then
  echo 'an ad-hoc build satisfied the release identity' >&2; exit 1
fi

# Hardened library validation needs a Team ID, which a self-signed certificate does not have.
HELPER="$UPDATE/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
if codesign -d --verbose "$HELPER" 2>&1 | grep -Eq 'flags=0x[0-9a-f]+\([^)]*runtime'; then
  echo 'Sparkle helpers were hardened without --hardened' >&2; exit 1
fi

echo 'A rebuilt self-signed app satisfies the previous identity; an ad-hoc rebuild does not'
