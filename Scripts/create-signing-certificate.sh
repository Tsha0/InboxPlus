#!/bin/bash
#
# Creates the self-signed code-signing certificate that every Inbox+ release is signed with.
# Run it once, ever. macOS remembers Full Disk Access and Automation grants by this certificate,
# so a release signed with a different one is a different app and every user re-grants access.
#
# Usage: Scripts/create-signing-certificate.sh <backup.p12> [keychain]
#
#   backup.p12   Where to write the certificate and private key. Store it somewhere safe and
#                offline; restoring it is the only way to sign future releases as the same app.
#   keychain     Defaults to the login keychain.
#
# Environment:
#   INBOXPLUS_CERTIFICATE_NAME       Defaults to "Inbox+ Release Signing".
#   INBOXPLUS_CERTIFICATE_PASSWORD   Protects the backup. Prompted for when unset.

set -euo pipefail

BACKUP="${1:?usage: Scripts/create-signing-certificate.sh <backup.p12> [keychain]}"
KEYCHAIN="${2:-$HOME/Library/Keychains/login.keychain-db}"
NAME="${INBOXPLUS_CERTIFICATE_NAME:-Inbox+ Release Signing}"

fail() { echo "error: $*" >&2; exit 1; }

[ ! -e "$BACKUP" ] || fail "$BACKUP already exists"
[ -f "$KEYCHAIN" ] || fail "keychain not found: $KEYCHAIN"
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  fail "\"$NAME\" is already in $KEYCHAIN. Releases must keep using it; do not create another."
fi

if [ -z "${INBOXPLUS_CERTIFICATE_PASSWORD:-}" ]; then
  read -rsp "Password for the backup: " INBOXPLUS_CERTIFICATE_PASSWORD; echo
  read -rsp "Repeat it: " CONFIRM; echo
  [ "$INBOXPLUS_CERTIFICATE_PASSWORD" = "$CONFIRM" ] || fail "passwords do not match"
fi
[ -n "$INBOXPLUS_CERTIFICATE_PASSWORD" ] || fail "the backup password cannot be empty"
export INBOXPLUS_CERTIFICATE_PASSWORD

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
umask 077

cat > "$WORK/certificate.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

# /usr/bin/openssl is LibreSSL, whose PKCS#12 encryption the macOS keychain can import. A Homebrew
# OpenSSL 3 export is rejected by `security import` unless made with -legacy.
# Twenty years: a release signed after expiry would no longer verify.
/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$WORK/certificate.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" \
  -passout env:INBOXPLUS_CERTIFICATE_PASSWORD -out "$WORK/identity.p12"

cp "$WORK/identity.p12" "$BACKUP"
security import "$BACKUP" -k "$KEYCHAIN" -P "$INBOXPLUS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\" in $KEYCHAIN"
echo "SHA-256: $(/usr/bin/openssl x509 -in "$WORK/certificate.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
echo
echo "Backup written to $BACKUP. Move it somewhere safe and offline, and keep its password."
echo "To sign releases on another Mac:"
echo "  security import <backup.p12> -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign"
echo
echo "Sign releases with:"
echo "  export INBOXPLUS_SIGNING_IDENTITY='$NAME'"
