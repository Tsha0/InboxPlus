# Third-party inventory

The generated [CycloneDX SBOM](sbom.cdx.json) lists dependency versions, licenses,
artifact hashes, and source locations. Regenerate it with:

```bash
swift Scripts/make-build-versions.swift
swift run InboxPlusRuntimeCLI sbom --output docs/sbom.cdx.json
```

Dependency pins are defined in:

- [`Package.swift`](../Package.swift)
- [`Runtime/Synapse/runtime-manifest.json`](../Runtime/Synapse/runtime-manifest.json)
- [`Runtime/Synapse/requirements.lock`](../Runtime/Synapse/requirements.lock)
- [`Sources/InboxPlusBridge/BridgeCatalog.swift`](../Sources/InboxPlusBridge/BridgeCatalog.swift)
- [`Sources/InboxPlusBridgeService/LibolmProvisioner.swift`](../Sources/InboxPlusBridgeService/LibolmProvisioner.swift)

`InboxPlusBuildVersions.swift` is generated from the Synapse manifest and the resolved Matrix SDK
version. CI regenerates it before checking the SBOM, so installed bundles report the same pins
as the build.

CPython 3.12.14 is bundled under the PSF-2.0 license. An explicit developer bootstrap with
`--python` can use a host-provided Python 3.12 instead.

Brand-mark SVGs in [`Scripts/brand-icons`](../Scripts/brand-icons) are from
[Simple Icons](https://simpleicons.org), version 13.20.0, under CC0-1.0.
The depicted marks remain trademarks of their respective owners; no affiliation
or endorsement is claimed.
