# Third-party dependency inventory

Everything Mimo executes that it did not write, with the exact version and the content hash that
was verified before it ran. Mimo is AGPL-3.0-or-later; every entry below is compatible.

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

All AGPL-3.0-or-later. SHA-256 values are copied verbatim from upstream's published
`sha256sums.txt` for the pinned tag and verified before the bytes are made executable. Every one of
these was downloaded and checked through `BridgeInstaller` — a pin that has never been tested
against real bytes is not a pin.

Each bridge carries **its own release tag**: the mautrix projects share a calendar-versioning scheme
but not a release train.

| Network | Repository | Version | Asset |
| --- | --- | --- | --- |
| Instagram | [mautrix/meta](https://github.com/mautrix/meta) | `v0.2607.0` | `mautrix-instagram-darwin-arm64` |
| Facebook Messenger | [mautrix/meta](https://github.com/mautrix/meta) | `v0.2607.0` | `mautrix-meta-darwin-arm64` |
| WhatsApp | [mautrix/whatsapp](https://github.com/mautrix/whatsapp) | `v0.2607.0` | `mautrix-whatsapp-darwin-arm64` |
| Telegram | [mautrix/telegram](https://github.com/mautrix/telegram) | `v0.2607.0` | `mautrix-telegram-darwin-arm64` |
| Google Messages | [mautrix/gmessages](https://github.com/mautrix/gmessages) | `v0.2605.0` | `mautrix-gmessages-darwin-arm64` |
| Google Voice | [mautrix/gvoice](https://github.com/mautrix/gvoice) | `v0.2605.0` | `mautrix-gvoice-darwin-arm64` |

The hashes are not repeated here. They live in `BridgeCatalog`, and `docs/sbom.cdx.json` is
generated from it — a hash transcribed into prose is a hash that will eventually disagree with the
one actually enforced.

iMessage has no artifact: it is reached through macOS itself and authenticates by permission grant.

### Networks deliberately absent

X, Slack, and LinkedIn are display-only coming-soon placeholders; they have no bridge artifacts.

| Network | Why |
| --- | --- |
| Discord | The current release is still the pre-`bridgev2` architecture. It installs and verifies, then exits immediately, because it does not speak the provisioning protocol every other bridge here uses. |
| Google Chat | Python-only; publishes no macOS binary, so there is nothing to checksum. |
| IRC | The maintained bridges are Python and Node projects with no pinned macOS release. |
| External Matrix | Needs multi-account support, which Mimo does not have. |

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

## Brand marks

| Name | Version | Licence | Notes |
| --- | --- | --- | --- |
| [Simple Icons](https://simpleicons.org) | `13.20.0` | CC0-1.0 | Source SVGs for the twelve network marks. Converted to Swift vector paths by `Scripts/make-platform-glyphs.swift`; nothing from the package is shipped or linked. |

The SVG files are CC0. The marks they depict remain the trademarks of their respective owners —
Mimo draws them to identify which network a conversation belongs to, which is what a messaging
client uses them for, and claims no affiliation with or endorsement by any of them.

The conversion happens once, at authoring time, so the app carries no SVG parser and no bundled
images. Regenerate with:

```sh
swift Scripts/make-platform-glyphs.swift Scripts/brand-icons \
  Sources/MimoUI/PlatformGlyphPaths.swift /tmp/badges.png
```

Look at the contact sheet it writes. Arc conversion is the error-prone part and a wrong logo is
obvious to the eye and invisible in a diff — the first run of this silently produced a blank
Discord, a Messenger with no bolt and a WhatsApp with no bubble.

## The generated inventory

`docs/sbom.cdx.json` is the machine-readable inventory, in CycloneDX 1.5, emitted from the same
pins the code enforces:

```sh
MimoRuntimeCLI sbom --output docs/sbom.cdx.json
```

It is deterministic — identical pins produce a byte-identical document — so two releases can be
diffed. Regenerate it whenever a pin changes; CI should fail if the checked-in copy is stale.

CycloneDX rather than a bespoke format because scanners already read it. `libolm` is reported as
having no package URL and therefore no advisory-database match; that gap is stated in the tool
output rather than left to be discovered.

## Reviewing a pin

When bumping any version, the hash must be re-read from upstream's published checksum file, never
computed from the download. After bumping a bridge, re-read its advertised login flows from a
running instance — `BridgeCatalog.expectedLoginFlowIDs` records only what was actually observed, and
drift against it is reported rather than silently accepted.
