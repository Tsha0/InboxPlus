# Third-party inventory

The generated [CycloneDX SBOM](sbom.cdx.json) is the full inventory. It records Flutter
dependencies, embedded Go connectors and build toolchains, with their exact versions. This page
explains what the SBOM cannot show: where each pin lives, which licenses carry obligations, and
which binary downloads need their own verification.

## How the inventory is generated

Regenerate the SBOM and the bundled notices with the commands in
[Generated files](../CONTRIBUTING.md#generated-files).

- The generator reads both pub lockfiles, `native/connectors/go.mod` and `go.sum`, and the Sparkle
  lock and artifact record in `native/updates`.
- It applies the reviewed licenses in [`dependency-licenses.json`](dependency-licenses.json). That
  file records the SHA-256 of each reviewed upstream license file.
- A new locked version needs a new review entry. The generator fails instead of guessing a license.
- The serial number is derived from the content, so the output is deterministic.
- The bundled [third-party notices](../apps/inboxplus/assets/third_party_notices.txt) come from
  the reviewed license and NOTICE files. The app shows them in **Settings → Open source licenses**.

What the SBOM does and does not claim:

- It lists build and test dependencies as well as runtime ones. A listed component does not
  necessarily ship on every platform.
- A pub SHA-256 describes the published package archive. A Go `h1:` value describes normalized
  module contents, so the SBOM stores it as a property and never labels it a raw archive SHA-256.
- The Go replacement of `github.com/imroc/req/v3` appears as the pinned source that is built,
  `github.com/beeper/req/v3`.
- Pillow (HPND license) generates the launcher icons. It is listed as a build tool and is not part
  of the installed app.
- The SBOM does not yet list every library inside the prebuilt native media binaries. Audit those
  payloads and include their notices before a release.

## Flutter application

- The app pins direct dependencies in [`pubspec.yaml`](../apps/inboxplus/pubspec.yaml) and
  [`pubspec.lock`](../apps/inboxplus/pubspec.lock).
- The storage package has its own [`pubspec.yaml`](../packages/inboxplus_storage/pubspec.yaml) and
  [`pubspec.lock`](../packages/inboxplus_storage/pubspec.lock).
- CI runs `pub get --enforce-lockfile`. Commit both lockfiles when you update a dependency.
- Android's Maven graph, including Gradle plugin classpaths, is pinned by
  [`android/gradle/locks`](../apps/inboxplus/android/gradle/locks) and authenticated by
  [`verification-metadata.xml`](../apps/inboxplus/android/gradle/verification-metadata.xml). Gradle
  enforces both in every build. To refresh them, see
  [Android dependency locks](../CONTRIBUTING.md#android-dependency-locks).

| Component | License | Role |
| --- | --- | --- |
| Flutter and Dart | BSD-3-Clause | Shared interface and application runtime |
| cupertino_icons | MIT | Classic desktop tray, people, compose and settings symbols |
| Drift | MIT | Typed SQLite records and transactions |
| sqlite3 Dart package | MIT | Native SQLite bindings and verified binary build hook |
| flutter_secure_storage | BSD-3-Clause | OS credential-store integration |
| unorm_dart | MIT | Unicode normalization for accent-insensitive contact suggestions |
| media_kit packages | MIT for the Dart and plugin source | Media playback. The native playback binaries have separate licenses |

The app and the storage package both select `source: sqlite3mc` for the pinned sqlite3 build hook.
The hook downloads SQLite3MultipleCiphers from the exact release of the sqlite3 package and
verifies the published SHA-256 of the platform artifact before it loads it. An unencrypted SQLite
build is not an acceptable substitute.

## macOS updater

- `native/updates/Package.swift` pins Sparkle **2.10.0**. The committed SwiftPM and Xcode locks pin
  its source revision.
- That revision declares the SHA-256 of the binary artifact, and SwiftPM verifies it before
  extraction.
- `native/updates/sparkle-artifact.json` records the same distribution and checksum for the SBOM.
- `LICENSE.sparkle` keeps the artifact's complete MIT, BSD-2-Clause and Zlib notices. The notices
  generator verifies them against reviewed hashes and bundles them with the app.

## Embedded connectors

Exact versions are in [`go.mod`](../native/connectors/go.mod) and content checksums are in
[`go.sum`](../native/connectors/go.sum). `build.sh` requires Go **1.27.3**, sets
`GOTOOLCHAIN=local` and `-mod=readonly`, and runs `go mod verify` before it compiles. The Android
and iOS builds compile the same source for their SDKs. Nothing downloads a bridge server at
runtime.

| Library | License |
| --- | --- |
| whatsmeow | MPL-2.0 |
| gotd/td | MIT |
| mautrix-meta | AGPL-3.0-or-later |
| openwechat | Apache-2.0 |
| Arikawa | ISC |
| mautrix-linkedin (linkedingo package) | AGPL-3.0-or-later |
| go-sqlite3 | MIT. The SQLite source keeps its upstream public-domain terms |

License obligations:

- The project is [AGPL-3.0-or-later](../LICENSE). The Meta and LinkedIn client code is linked into
  the app, not kept in a separate bridge executable.
- Distributing the combined app requires the corresponding AGPL source and notices. The app does
  not become MIT because some of its libraries are MIT.
- Preserve the other copyleft notices, including the MPL source obligations and the transitive
  libsignal GPL license.
- The LinkedIn repository's extra licensing exceptions name specific third parties. Inbox+ uses its
  AGPL terms.
- Only the network clients are embedded, without the Matrix bridge runtime.
- Check store terms, signing and redistribution obligations for each real release. A successful
  development build proves none of them.

## Native media artifacts

The media_kit native packages make extra downloads that pub's archive checksum does not
authenticate. The runners verify each download before it can be extracted or packaged.

- **Apple.** The `media_kit_libs_macos_video` and `media_kit_libs_ios_video` Makefiles pin
  `libmpv-darwin-build` **v0.6.0**, the `video-default` payload and the upstream SHA-256 values.
- **Android.** [`verify-media-artifacts.py`](../Scripts/verify-media-artifacts.py) pins the four
  **v1.1.7** JARs with the SHA-256 digests of the official GitHub release assets. The plugin's
  older MD5 validation still runs, but it is not the trust check.
- **Windows.** The same script pins the **2023-09-24 / mpv 652a1dd** and **ANGLE v1.0.1** archives.
  Upstream publishes only MD5 for these assets. Our SHA-256 pins were computed from the exact HTTPS
  release assets after they matched the upstream MD5 values. Upstream did not publish them.
- **Linux.** The plugin uses the system `libmpv` and the system allocator. The runner disables its
  optional MD5-only mimalloc source download.

The mpv, FFmpeg, codec and ANGLE payloads carry their own licenses. The MIT license on the Dart
wrapper does not cover those binaries. A release must include the matching native library notices,
license texts and any required source or relinking information for the exact build configuration.
The current inventory does not certify that this obligation is complete.

## Brand marks

The brand-mark SVGs in [`Scripts/brand-icons`](../Scripts/brand-icons) come from
[Simple Icons](https://simpleicons.org) version 13.20.0, under CC0-1.0. The marks remain trademarks
of their owners. No affiliation or endorsement is claimed.
