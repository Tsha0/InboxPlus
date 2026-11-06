# Third-party inventory

The generated [CycloneDX SBOM](sbom.cdx.json) records the repository's retained Swift runtime,
Flutter dependencies and embedded Go connectors. It includes build/test dependencies as well as
runtime dependencies; it is not a statement that every listed component ships on every platform.
Regenerate it from the repository root on macOS:

```bash
python3 Scripts/generate-sbom.py
python3 Scripts/generate-third-party-notices.py
```

The generator invokes the existing Swift CLI for its inventory, reads both committed pub lockfiles
and `native/connectors/go.mod` / `go.sum`, then applies the reviewed licenses in
[`dependency-licenses.json`](dependency-licenses.json). The content-derived serial is deterministic.
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
| go-sqlite3 | `v1.14.52` | MIT; SQLite source has its upstream public-domain terms |

The root project is [AGPL-3.0-or-later](../LICENSE). Meta client code is now linked into the app,
rather than kept only in a separate bridge executable. Distributing the combined app requires the
corresponding AGPL source and notices; its use does not become MIT because some neighboring
libraries are MIT. Preserve other copyleft notices, including MPL source obligations and the
transitive libsignal GPL license. Store distribution terms, signing and redistribution obligations
must be checked for an actual release rather than inferred from a successful development build.

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

## Retained Swift application

The previous macOS app still uses these independent pins during migration:

- [`Package.swift`](../Package.swift)
- [`Runtime/Synapse/runtime-manifest.json`](../Runtime/Synapse/runtime-manifest.json)
- [`Runtime/Synapse/requirements.lock`](../Runtime/Synapse/requirements.lock)
- [`BridgeCatalog.swift`](../Sources/InboxPlusBridge/BridgeCatalog.swift)
- [`LibolmProvisioner.swift`](../Sources/InboxPlusBridgeService/LibolmProvisioner.swift)

Its bundled CPython is PSF-2.0. Sparkle 2.10.0 and its installer helpers are MIT and upstream
component licenses. The old app's `ThirdPartyNotices` directory contains Sparkle's full license;
that does not provide the new Flutter app's native media notices.

Brand-mark SVGs in [`Scripts/brand-icons`](../Scripts/brand-icons) are from
[Simple Icons](https://simpleicons.org), version 13.20.0, under CC0-1.0. The marks remain trademarks
of their owners; no affiliation or endorsement is claimed.
