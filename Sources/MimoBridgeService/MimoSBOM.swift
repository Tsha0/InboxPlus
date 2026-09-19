import Foundation
import MimoBridge
import MimoRuntime

/// Assembles Mimo's bill of materials from the pins that actually govern what runs.
///
/// Generated from `BridgeCatalog` and the runtime manifest rather than maintained by hand: an
/// inventory written separately from the thing it describes goes stale the first time someone bumps
/// a version, and a stale inventory is believed anyway.
public enum MimoSBOM {
    public static func components(
        bridges: [BridgeDescriptor] = BridgeCatalog.all,
        synapseVersion: String = "1.158.0",
        matrixSDKVersion: String = "26.08.11"
    ) -> [SBOMComponent] {
        var components: [SBOMComponent] = [
            SBOMComponent(
                name: "matrix-rust-components-swift",
                version: matrixSDKVersion,
                kind: .framework,
                license: "Apache-2.0",
                sourceURL: "https://github.com/matrix-org/matrix-rust-components-swift",
                purl: "pkg:swift/github.com/matrix-org/matrix-rust-components-swift@\(matrixSDKVersion)",
                notes: "Checksum-verified binary xcframework, pinned exactly so protocol drift "
                    + "cannot arrive through a version range."
            ),
            SBOMComponent(
                name: "synapse",
                version: synapseVersion,
                kind: .application,
                license: "AGPL-3.0-or-later",
                sourceURL: "https://github.com/element-hq/synapse",
                purl: "pkg:pypi/matrix-synapse@\(synapseVersion)",
                notes: "Installed into a profile-local virtualenv from a locked requirements file."
            ),
            SBOMComponent(
                name: "libolm",
                version: LibolmProvisioner.version,
                kind: .library,
                license: "Apache-2.0",
                sha256: LibolmProvisioner.sourceSHA256,
                sourceURL: "https://gitlab.matrix.org/matrix-org/olm",
                downloadURL: LibolmProvisioner.sourceURL.absoluteString,
                // Recorded because it matters to anyone auditing this: the shipped library is not
                // byte-identical to upstream's source, and the reason is in the acceptance doc.
                notes: "Built from a checksum-verified tarball with a pinned one-line patch; "
                    + "upstream is archived and does not compile with a current clang."
            ),
        ]

        for bridge in bridges {
            guard let artifact = bridge.artifact else { continue }
            let repository = bridge.sourceURL.lastPathComponent
            components.append(
                SBOMComponent(
                    name: artifact.assetName,
                    version: bridge.version,
                    kind: .application,
                    license: bridge.license,
                    sha256: artifact.sha256,
                    sourceURL: bridge.sourceURL.absoluteString,
                    downloadURL: artifact.downloadURL.absoluteString,
                    purl: "pkg:github/mautrix/\(repository)@\(bridge.version)",
                    notes: "Downloaded on demand and verified before it is made executable."
                )
            )
        }
        return components
    }

    public static func bill(applicationVersion: String) -> SoftwareBillOfMaterials {
        SoftwareBillOfMaterials(components: components(), applicationVersion: applicationVersion)
    }
}
