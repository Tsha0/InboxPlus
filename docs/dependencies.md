# Third-party dependency inventory

Everything Pallo executes that it did not write, with the exact version and the content hash that
was verified before it ran. Pallo is AGPL-3.0-or-later; every entry below is compatible.

Only `darwin-arm64` artifacts are pinned. Pinning a hash for a platform nobody has verified end to
end would be a hash nobody has checked.

## Build-time (Swift Package Manager)

| Name | Version | Licence | Notes |
| --- | --- | --- | --- |
| [matrix-rust-components-swift](https://github.com/matrix-org/matrix-rust-components-swift) | `26.08.11` (exact) | Apache-2.0 | Checksum-verified 279 MB binary xcframework. Pinned exactly — SDK/bridge protocol drift must never arrive silently through a version range. |

## Runtime, fetched into a profile

### Homeserver

| Name | Version | Licence | Verification |
| --- | --- | --- | --- |
| Synapse | `1.158.0` | AGPL-3.0-or-later | Installed from `Runtime/Synapse/requirements.lock` into a profile-local virtualenv; the receipt is validated against `runtime-manifest.json`. |
| CPython | 3.12 (host-provided) | PSF-2.0 | Supplied by the operator, recorded in the bootstrap receipt. |

### Network bridges (`BridgeCatalog`)

All at mautrix tag `v0.2607.0`, all AGPL-3.0-or-later. SHA-256 values are copied verbatim from
upstream's published `sha256sums.txt` and verified before the bytes are made executable.

| Network | Repository | Asset | SHA-256 |
| --- | --- | --- | --- |
| Instagram | [mautrix/meta](https://github.com/mautrix/meta) | `mautrix-instagram-darwin-arm64` | `c7bc6e81def6a23f0f2e8359d7079e86b82723dfb9082b22ad642a9a8912173b` |
| Facebook Messenger | [mautrix/meta](https://github.com/mautrix/meta) | `mautrix-meta-darwin-arm64` | `a468cca261034f1a93efc927113ab3d07411836e7c5dd68b7c71e59bdfb17dfb` |
| WhatsApp | [mautrix/whatsapp](https://github.com/mautrix/whatsapp) | `mautrix-whatsapp-darwin-arm64` | `f5c0291e4315a8cf70e836b7707f4e6503353b021a115eebb3a6b18f1b9acfbc` |
| Telegram | [mautrix/telegram](https://github.com/mautrix/telegram) | `mautrix-telegram-darwin-arm64` | `0e2c2ded1773533c691b902b3d0fc4ec87a2f5d3170cd714f7e9e3e494481dd3` |

iMessage has no artifact: it is reached through macOS itself and authenticates by permission grant.

### libolm

| Name | Version | Licence | SHA-256 (source tarball) |
| --- | --- | --- | --- |
| [libolm](https://gitlab.matrix.org/matrix-org/olm) | `3.2.16` | Apache-2.0 | `1e90f9891009965fd064be747616da46b232086fe270b77605ec9bda34272a68` |

Built from source rather than vendored as a binary, because every prebuilt mautrix binary links
`@rpath/libolm.3.dylib` and no current macOS supplies it — libolm is end-of-life and Homebrew has
dropped it.

A pinned one-hunk patch is applied before building: libolm 3.2.16 does not compile with a current
clang, because `List::operator=` declares its cursor `T * const` and then increments it. That
function has never compiled anywhere and so has never run. libolm is archived and `master` carries
the same defect, so upstream will not fix it. The patch is pinned as an exact before/after pair — if
the source ever stops matching verbatim, the build fails rather than applying a fuzzy edit to a
crypto library.

Requires `cmake` on the host (`brew install cmake`).

## Reviewing a pin

When bumping any version, the hash must be re-read from upstream's published checksum file, never
computed from the download. After bumping a bridge, re-read its advertised login flows from a
running instance — `BridgeCatalog.expectedLoginFlowIDs` records only what was actually observed, and
drift against it is reported rather than silently accepted.
