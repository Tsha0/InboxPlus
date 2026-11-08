#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$PROJECT_DIR/../../.." && pwd)
output_root="$DERIVED_FILE_DIR/inboxplus-connectors"
mkdir -p "$output_root"

case "${PLATFORM_NAME:-macosx}" in
  macosx) target=macos; library=libinboxplus_connectors.dylib ;;
  iphoneos) target=ios; library=libinboxplus_connectors.a ;;
  iphonesimulator) target=ios-simulator; library=libinboxplus_connectors.a ;;
  *) printf 'Unsupported Apple platform.\n' >&2; exit 1 ;;
esac

inputs=()
for architecture in $ARCHS; do
  case "$architecture" in
    arm64) go_architecture=arm64 ;;
    x86_64) go_architecture=amd64 ;;
    *) printf 'Unsupported Apple architecture.\n' >&2; exit 1 ;;
  esac
  printf 'connector_architecture_start target=%s arch=%s\n' "$target" "$go_architecture"
  started=$SECONDS
  GOARCH="$go_architecture" bash "$repository_root/native/connectors/build.sh" "$target" "$output_root/$architecture"
  printf 'connector_architecture_done target=%s arch=%s seconds=%s\n' "$target" "$go_architecture" "$((SECONDS - started))"
  inputs+=("$output_root/$architecture/$library")
done

if [[ "$target" == macos ]]; then
  destination="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
else
  destination="$BUILT_PRODUCTS_DIR"
fi
mkdir -p "$destination"
xcrun lipo -create "${inputs[@]}" -output "$destination/$library"
if [[ "$target" == macos ]]; then
  chmod 755 "$destination/$library"
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$destination/$library"
fi
