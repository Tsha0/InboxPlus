# Third-party inventory

The generated [CycloneDX SBOM](sbom.cdx.json) records Flutter dependencies, embedded Go connectors
and build toolchains. It includes build/test dependencies as well as runtime dependencies; it is not a statement that every listed component ships on every platform.
Regenerate it from the repository root:

```bash
python3 Scripts/generate-sbom.py
python3 Scripts/generate-third-party-notices.py
```

The generator reads both committed pub lockfiles, `native/connectors/go.mod` / `go.sum`, and the
Sparkle lock and artifact record in `native/updates`, then applies the reviewed licenses in [`dependency-licenses.json`](dependency-licenses.json). The content-derived serial is deterministic.
Bundled [third-party notices](../apps/inboxplus_flutter/assets/third_party_notices.txt) are generated
from the reviewed package license and NOTICE files and exposed through Settings → Open source
licenses. Resolve both pub lockfiles and run `go -C native/connectors mod download` before
regenerating notices. `PUB_CACHE` and `GO_BINARY` can select custom cache/toolchain locations.
License evidence records SHA-256 hashes of reviewed upstream license files. A new locked version
needs a new review entry; the generator fails rather than inventing a license.

Pub SHA-256 values describe published package archives. Go's `h1:` values describe normalized
module contents and are stored as properties, **not mislabeled as raw archive SHA-256 hashes**.
The Go replacement of `github.com/imroc/req/v3` is represented by the actual pinned
`github.com/beeper/req/v3` source. The inventory does not yet enumerate every third-party library
inside prebuilt native media binaries; audit those payloads and include their notices before release.

Flutter launcher icons are generated with the development-only Pillow **10.4.0** tool (HPND
license). It is included in the inventory as a build tool and is not part of the installed app.

## Flutter application

Direct dependency pins live in
[`pubspec.yaml`](../apps/inboxplus_flutter/pubspec.yaml) and
[`pubspec.lock`](../apps/inboxplus_flutter/pubspec.lock). The reusable storage package has its own
[`pubspec.yaml`](../packages/inboxplus_storage/pubspec.yaml) and
[`lockfile`](../packages/inboxplus_storage/pubspec.lock). Use `pub get --enforce-lockfile` in CI and
include both lockfiles when updating dependencies.

Android's Maven graph, including Gradle plugin classpaths, is additionally pinned by
[`android/gradle/locks`](../apps/inboxplus_flutter/android/gradle/locks) and authenticated by
[`verification-metadata.xml`](../apps/inboxplus_flutter/android/gradle/verification-metadata.xml).
Gradle enforces both during normal builds. See the Android lock refresh workflow in
[Contributing](../CONTRIBUTING.md#packaging-checks) when updating Android dependencies.

| Component | License and role |
| --- | --- |
| Flutter / Dart | BSD-3-Clause; shared interface and application runtime |
| cupertino_icons 2.0.0 | MIT; classic desktop tray, people, compose and settings symbols |
| Drift | MIT; typed SQLite records and transactions |
| sqlite3 Dart package | MIT; native SQLite bindings and verified binary build hook |
| flutter_secure_storage | BSD-3-Clause; OS credential-store integration |
| unorm_dart 0.3.3 | MIT; Unicode normalization for accent-insensitive contact suggestions |
| media_kit packages | MIT for the Dart/plugin source; native playback dependencies have separate licenses |

The root consuming app and storage package both select `source: sqlite3mc` for the pinned sqlite3
build hook. It downloads SQLite3MultipleCiphers from the sqlite3 package's exact release and verifies
the platform artifact's published SHA-256 before loading it. A normal unencrypted SQLite build is
not an acceptable substitution.

## macOS updater

`native/updates/Package.swift` pins Sparkle **2.10.0**. The committed SwiftPM and Xcode locks pin its
source revision; that revision declares the binary artifact's SHA-256, verified by SwiftPM before
extraction. `native/updates/sparkle-artifact.json` records that same distribution and checksum for
the SBOM. `LICENSE.sparkle` preserves the artifact's complete MIT, BSD-2-Clause and Zlib notices,
which the notices generator verifies against reviewed hashes and bundles with the app.

## Embedded connectors

Exact versions are in [`go.mod`](../native/connectors/go.mod); normalized content checksums are
in [`go.sum`](../native/connectors/go.sum). `build.sh` requires Go **1.27.3**, sets
`GOTOOLCHAIN=local` and `-mod=readonly`, and runs `go mod verify` before compilation. Android and iOS
builds compile the same source for their native SDKs; no bridge server is downloaded at runtime.

| Library | Exact pin | License |
| --- | --- | --- |
| whatsmeow | `v0.0.0-20261102152715-54038813c47f` | MPL-2.0 |
| gotd/td | `v0.163.0` | MIT |
| mautrix-meta | `v0.2610.1-0.20261103213641-69a505d69039` | AGPL-3.0-or-later |
| openwechat | `v1.4.11-0.20250102030116-635e5561f319` | Apache-2.0 |
| Arikawa | `v3.6.1-0.20261031043016-e170775edee6` | ISC |
| mautrix-linkedin (linkedingo package) | `v0.2609.1-0.20261105130905-ff697e9152a8` | AGPL-3.0-or-later |
| go-sqlite3 | `v1.14.52` | MIT; SQLite source has its upstream public-domain terms |

The root project is [AGPL-3.0-or-later](../LICENSE). Meta and LinkedIn client code is linked into the app,
rather than kept only in a separate bridge executable. Distributing the combined app requires the
corresponding AGPL source and notices; its use does not become MIT because some neighboring
libraries are MIT. Preserve other copyleft notices, including MPL source obligations and the
transitive libsignal GPL license. Store distribution terms, signing and redistribution obligations
must be checked for an actual release rather than inferred from a successful development build.
The LinkedIn repository's additional licensing exceptions name specific third parties; Inbox+
uses its AGPL terms. Only the network clients are embedded, without the Matrix bridge runtime.

## Native media artifacts

The selected media_kit native packages contain extra downloads that pub's archive checksum alone
does not authenticate. The runners verify them before they can be extracted or packaged:

- Apple: `media_kit_libs_macos_video` and `media_kit_libs_ios_video` Makefiles pin
  `libmpv-darwin-build` **v0.6.0**, the `video-default` payload, and upstream SHA-256 values.
- Android: [`verify-media-artifacts.py`](../Scripts/verify-media-artifacts.py) pins the four
  **v1.1.7** JARs using the official GitHub release asset SHA-256 digests. The plugin's older MD5
  validation is additional, not the trust check.
- Windows: the same script pins **2023-09-24 / mpv 652a1dd** and **ANGLE v1.0.1** archives.
  Upstream publishes only MD5 for these assets and its GitHub API exposes no SHA-256 digest.
  Our SHA-256 pins were established from the exact HTTPS release assets after matching those
  upstream MD5 values; they are not represented as upstream-published SHA-256 values.
- Linux: the plugin uses the system `libmpv` and system allocator. Its optional MD5-only mimalloc
  source download is disabled in the runner.

The mpv/FFmpeg/codec payloads and ANGLE include their own licenses. The MIT license on the Dart
wrapper does not cover those binaries. A release must include the matching native library notices,
license texts and required source/relinking information, using the exact build's configuration.
The current development inventory does not certify that release obligation as complete.

## Brand marks

Brand-mark SVGs in [`Scripts/brand-icons`](../Scripts/brand-icons) are from
[Simple Icons](https://simpleicons.org), version 13.20.0, under CC0-1.0. The marks remain trademarks
of their owners; no affiliation or endorsement is claimed.
