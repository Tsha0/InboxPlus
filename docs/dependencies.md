# Third-party inventory

The generated [CycloneDX SBOM](sbom.cdx.json) lists every dependency and toolchain with its exact
version. It includes build and test tools, so a listed component does not necessarily ship. To
regenerate it, see [Generated files](../CONTRIBUTING.md#generated-files).

- Each locked version needs a reviewed license entry in
  [`dependency-licenses.json`](dependency-licenses.json).
- The app shows the bundled [third-party notices](../apps/inboxplus/assets/third_party_notices.txt)
  in **Settings → Open source licenses**.

## Flutter application

Pins are in the [app](../apps/inboxplus/pubspec.lock) and
[storage package](../packages/inboxplus_storage/pubspec.lock) lockfiles. Android's Maven pins are
in [`android/gradle/locks`](../apps/inboxplus/android/gradle/locks) and
[`verification-metadata.xml`](../apps/inboxplus/android/gradle/verification-metadata.xml).

| Component | License | Role |
| --- | --- | --- |
| Flutter and Dart | BSD-3-Clause | Interface and application runtime |
| cupertino_icons | MIT | Desktop tray, people, compose and settings symbols |
| Drift | MIT | Typed SQLite records and transactions |
| sqlite3 Dart package | MIT | SQLite bindings. Its build hook downloads SQLite3MultipleCiphers for database encryption |
| flutter_secure_storage | BSD-3-Clause | OS credential store |
| unorm_dart | MIT | Unicode normalization for contact suggestions |
| media_kit packages | MIT for the Dart and plugin source | Media playback |
| Pillow 10.4.0 | HPND | Launcher icon generation. Build tool only |

Every app that uses the storage package must select `source: sqlite3mc` for the sqlite3 build hook.
An unencrypted SQLite build is not an acceptable substitute.

## macOS updater

| Component | License | Pin |
| --- | --- | --- |
| Sparkle 2.10.0 | MIT, BSD-2-Clause and Zlib | `native/updates/Package.swift`, both Xcode `Package.resolved` files and `native/updates/sparkle-artifact.json` |

`native/updates/LICENSE.sparkle` keeps Sparkle's complete notices.

## Embedded connectors

Pins are in [`go.mod`](../native/connectors/go.mod) and [`go.sum`](../native/connectors/go.sum).

| Library | License |
| --- | --- |
| whatsmeow | MPL-2.0 |
| gotd/td | MIT |
| mautrix-meta | AGPL-3.0-or-later |
| openwechat | Apache-2.0 |
| Arikawa | ISC |
| mautrix-linkedin (linkedingo package) | AGPL-3.0-or-later |
| go-sqlite3 | MIT. The SQLite source is public domain |
| beeper/req (replaces imroc/req) | MIT |

License obligations:

- The project is [AGPL-3.0-or-later](../LICENSE). The Meta and LinkedIn clients are linked into the
  app, so distributing it requires the corresponding AGPL source and notices.
- Preserve the other copyleft notices, including the MPL source obligations and the transitive
  libsignal GPL license.
- The LinkedIn repository's extra licensing exceptions name specific third parties. Inbox+ uses its
  AGPL terms.
- Check store terms, signing and redistribution obligations for each real release.

## Native media binaries

media_kit downloads native binaries that pub's checksum does not cover. Each one is pinned by
SHA-256.

| Platform | Binary | Pinned in |
| --- | --- | --- |
| macOS and iOS | `libmpv-darwin-build` v0.6.0, `video-default` payload | The `media_kit_libs_macos_video` and `media_kit_libs_ios_video` Makefiles |
| Android | media_kit JARs v1.1.7 | [`verify-media-artifacts.py`](../Scripts/verify-media-artifacts.py) |
| Windows | mpv 2023-09-24 (652a1dd) and ANGLE v1.0.1 | [`verify-media-artifacts.py`](../Scripts/verify-media-artifacts.py) |
| Linux | System `libmpv` | Not downloaded |

- Upstream publishes only MD5 for the Windows archives. Our SHA-256 pins were computed from the
  release assets after they matched the upstream MD5 values.
- The mpv, FFmpeg, codec and ANGLE binaries carry their own licenses, which the Dart wrapper's MIT
  license does not cover.
- The SBOM does not yet list every library inside these binaries. Before a release, audit them and
  include their notices, license texts and any required source or relinking information.

## Brand marks

The brand-mark SVGs in [`Scripts/brand-icons`](../Scripts/brand-icons) come from
[Simple Icons](https://simpleicons.org) 13.20.0, under CC0-1.0. The marks remain trademarks of
their owners. No affiliation or endorsement is claimed.
