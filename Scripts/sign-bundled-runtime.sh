#!/bin/bash
# Sign native modules and interpreters before the outer app. Run after all runtime copying.
set -euo pipefail
RUNTIME="${1:?runtime directory required}"
IDENTITY="${2:--}"
# --hardened is for notarized Developer ID releases; see Scripts/embed-sparkle.sh.
HARDENED="${3:-}"
case "$HARDENED" in ''|--hardened) ;; *) echo "error: unknown option $HARDENED" >&2; exit 1 ;; esac
while IFS= read -r -d '' FILE; do
  if /usr/bin/file -b "$FILE" | /usr/bin/grep -q 'Mach-O'; then
    # Re-signing wheel libraries can fail when their existing signature was generated
    # under a different install ID. Remove it before applying the bundle's identity.
    if codesign -d "$FILE" >/dev/null 2>&1; then
      codesign --remove-signature "$FILE"
    fi
    if [ -n "$HARDENED" ]; then
      codesign --force --timestamp --options runtime --sign "$IDENTITY" "$FILE"
    else
      codesign --force --sign "$IDENTITY" "$FILE"
    fi
  fi
done < <(find "$RUNTIME" -type f \( -name "*.so" -o -name "*.dylib" -o -name "python3.12" \) -print0)
