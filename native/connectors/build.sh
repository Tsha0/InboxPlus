#!/usr/bin/env bash
set -euo pipefail

connector_root=$(cd "$(dirname "$0")" && pwd)
cd "$connector_root"
go_binary=${GO_BINARY:-go}
export GOTOOLCHAIN=local
if [[ "$($go_binary env GOVERSION)" != "go1.27.3" ]]; then
  printf 'Go 1.27.3 is required; set GO_BINARY to the verified pinned SDK.\n' >&2
  exit 1
fi
export CGO_ENABLED=1
export GOFLAGS=-mod=readonly
target=${1:-host}
if [[ "$target" == ios && "${SDK_NAME:-}" == iphonesimulator* ]]; then target=ios-simulator; fi
output=${2:-"$connector_root/build"}
mkdir -p "$output"
output=$(cd "$output" && pwd)
"$go_binary" mod verify

build_shared() {
  if [[ "${INBOXPLUS_CONNECTORS_BUILD_CACHE:-}" != "" && "$("$go_binary" env GOOS)" == darwin ]]; then
    python3 "$connector_root/../../Scripts/build-connectors-cache.py" "$go_binary" "$1" "$INBOXPLUS_CONNECTORS_BUILD_CACHE"
  else
    time "$go_binary" build -trimpath -buildmode=c-shared -o "$1" .
  fi
}

configure_macos() {
  sdk=$(xcrun --sdk macosx --show-sdk-path)
  export CC="$(xcrun --sdk macosx --find clang)"
  macos_target=${MACOSX_DEPLOYMENT_TARGET:-15.0}
  export MACOSX_DEPLOYMENT_TARGET="$macos_target"
  export SDKROOT="$sdk"
  export CGO_CFLAGS="${CGO_CFLAGS:-} -isysroot $sdk -mmacosx-version-min=$macos_target"
  export CGO_LDFLAGS="${CGO_LDFLAGS:-} -isysroot $sdk -mmacosx-version-min=$macos_target"
  case "${CURRENT_ARCH:-}" in
    arm64) export GOARCH=arm64 ;;
    x86_64) export GOARCH=amd64 ;;
  esac
}

case "$target" in
  host)
    case "$("$go_binary" env GOOS)" in
      darwin) configure_macos; build_shared "$output/libinboxplus_connectors.dylib" ;;
      linux) build_shared "$output/libinboxplus_connectors.so" ;;
      windows) build_shared "$output/inboxplus_connectors.dll" ;;
      *) printf 'Unsupported host.\n' >&2; exit 1 ;;
    esac
    ;;
  macos)
    export GOOS=darwin
    configure_macos
    build_shared "$output/libinboxplus_connectors.dylib"
    ;;
  linux)
    export GOOS=linux
    build_shared "$output/libinboxplus_connectors.so"
    ;;
  windows)
    export GOOS=windows
    build_shared "$output/inboxplus_connectors.dll"
    ;;
  ios|ios-simulator)
    export GOOS=ios
    export GOARCH=${GOARCH:-${CURRENT_ARCH:-arm64}}
    [[ "$GOARCH" != x86_64 ]] || export GOARCH=amd64
    if [[ "$target" == ios ]]; then
      sdk=$(xcrun --sdk iphoneos --show-sdk-path)
      export CC="$(xcrun --sdk iphoneos --find clang)"
      export CGO_CFLAGS="-isysroot $sdk -miphoneos-version-min=15.0"
      export CGO_LDFLAGS="-isysroot $sdk -miphoneos-version-min=15.0 -framework CoreFoundation -framework Security -lresolv"
    else
      sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
      export CC="$(xcrun --sdk iphonesimulator --find clang)"
      clang_arch=$GOARCH
      [[ "$GOARCH" != amd64 ]] || clang_arch=x86_64
      export CGO_CFLAGS="-isysroot $sdk -target $clang_arch-apple-ios15.0-simulator"
      export CGO_LDFLAGS="-isysroot $sdk -target $clang_arch-apple-ios15.0-simulator -framework CoreFoundation -framework Security -lresolv"
    fi
    "$go_binary" build -trimpath -buildmode=c-archive -o "$output/libinboxplus_connectors.a" .
    ;;
  android)
    : "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the pinned Android NDK installation}"
    ndk_bin=
    for directory in "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin; do
      if [[ -d "$directory" ]]; then ndk_bin=$directory; break; fi
    done
    if [[ -z "$ndk_bin" ]]; then printf 'Android NDK LLVM compiler was not found.\n' >&2; exit 1; fi
    export GOOS=android
    android_api=${ANDROID_API:-24}
    for abi in arm64-v8a armeabi-v7a x86_64; do
      case "$abi" in
        arm64-v8a) export GOARCH=arm64; compiler=aarch64-linux-android ;;
        armeabi-v7a) export GOARCH=arm GOARM=7; compiler=armv7a-linux-androideabi ;;
        x86_64) export GOARCH=amd64; compiler=x86_64-linux-android ;;
      esac
      export CC="$ndk_bin/$compiler$android_api-clang"
      mkdir -p "$output/$abi"
      build_shared "$output/$abi/libinboxplus_connectors.so"
    done
    ;;
  *) printf 'Usage: build.sh [host|macos|linux|windows|ios|ios-simulator|android] [output-directory]\n' >&2; exit 1 ;;
esac
