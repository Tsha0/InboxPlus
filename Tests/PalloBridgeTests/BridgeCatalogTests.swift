import Foundation
import Testing
@testable import PalloBridge
@testable import PalloCore

@Test func theCatalogIsStructurallySound() throws {
    try BridgeCatalog.validate()
}

@Test func everyDownloadableBridgePinsAFullSHA256OverHTTPS() {
    for descriptor in BridgeCatalog.all {
        guard let artifact = descriptor.artifact else {
            #expect(descriptor.runtimeKind == .nativeAdapter, "\(descriptor.id) has no artifact")
            continue
        }
        #expect(artifact.sha256.count == 64, "\(descriptor.id) checksum is not a SHA-256")
        #expect(
            artifact.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase },
            "\(descriptor.id) checksum is not lowercase hex"
        )
        #expect(artifact.downloadURL.scheme == "https", "\(descriptor.id) is fetched insecurely")
        #expect(
            artifact.downloadURL.absoluteString.contains(descriptor.version),
            "\(descriptor.id) download URL is not pinned to its recorded version"
        )
    }
}

@Test func aMalformedChecksumIsRejected() {
    let broken = BridgeDescriptor(
        id: "broken",
        platform: .signal,
        displayName: "Broken",
        version: "v1",
        runtimeKind: .goBinary,
        credentialStyle: .qrCode,
        artifact: BridgeArtifact(
            assetName: "x",
            sha256: "not-a-hash",
            downloadURL: URL(string: "https://example.com/x")!
        ),
        expectedLoginFlowIDs: [],
        license: "AGPL-3.0-or-later",
        sourceURL: URL(string: "https://example.com")!
    )
    #expect(throws: BridgeCatalogError.malformedChecksum(bridge: "broken", value: "not-a-hash")) {
        try BridgeCatalog.validate([broken])
    }
}

@Test func aBridgeIdentifierUnsafeForAnAppserviceRegistrationIsRejected() {
    let hostile = BridgeDescriptor(
        id: "../../etc/passwd",
        platform: .signal,
        displayName: "Hostile",
        version: "v1",
        runtimeKind: .nativeAdapter,
        credentialStyle: .systemPermissions,
        artifact: nil,
        expectedLoginFlowIDs: [],
        license: "AGPL-3.0-or-later",
        sourceURL: URL(string: "https://example.com")!
    )
    #expect(throws: BridgeCatalogError.unsafeIdentifier("../../etc/passwd")) {
        try BridgeCatalog.validate([hostile])
    }
}

@Test func twoBridgesCannotClaimTheSamePlatform() {
    #expect(throws: BridgeCatalogError.duplicatePlatform(.instagram)) {
        try BridgeCatalog.validate([BridgeCatalog.instagram, BridgeCatalog.instagram])
    }
}

@Test func thePickerListsEverySupportedPlatformAndPutsTheAvailableOnesFirst() {
    let order = BridgeCatalog.pickerOrder
    #expect(Set(order) == Set(Platform.allCases), "the picker must never hide a platform")
    #expect(order.count == 16)

    let availableCount = order.prefix { BridgeCatalog.isAvailable($0) }.count
    #expect(availableCount == BridgeCatalog.all.count)
    #expect(
        order.dropFirst(availableCount).allSatisfy { !BridgeCatalog.isAvailable($0) },
        "an available network was sorted below an unavailable one"
    )
}

@Test func askingForAnUnsupportedNetworkFailsWithAnActionableReason() {
    // Google Chat publishes no macOS binary, so there is nothing to checksum and nothing to run.
    #expect(throws: BridgeCatalogError.unsupportedPlatform(.googleChat)) {
        try BridgeCatalog.require(.googleChat)
    }
    #expect(BridgeCatalogError.unsupportedPlatform(.googleChat).description.contains("Google Chat"))
}

@Test func anUnavailableNetworkSaysWhyRatherThanJustBeingAbsent() throws {
    for platform in Platform.allCases {
        let reason = BridgeCatalog.unavailabilityReason(for: platform)
        if BridgeCatalog.isAvailable(platform) {
            #expect(reason == nil)
        } else {
            #expect(reason?.isEmpty == false)
        }
    }
    // The three the design lists but Phase 6 could not deliver each name their own obstacle.
    #expect(BridgeCatalog.unavailabilityReason(for: .googleChat)?.contains("Python-only") == true)
    #expect(BridgeCatalog.unavailabilityReason(for: .irc)?.contains("no pinned macOS") == true)
    #expect(BridgeCatalog.unavailabilityReason(for: .matrix)?.contains("multi-account") == true)
}

@Test func everyPhase6BridgePinsItsOwnReleaseTag() throws {
    // The mautrix projects share a version scheme but not a release train; assuming one tag across
    // all of them would point several downloads at tags that do not exist.
    for descriptor in BridgeCatalog.all {
        guard let artifact = descriptor.artifact else { continue }
        #expect(
            artifact.downloadURL.absoluteString.contains("/download/\(descriptor.version)/"),
            "\(descriptor.id) downloads from a tag that is not the version it claims"
        )
        #expect(artifact.downloadURL.absoluteString.hasSuffix(artifact.assetName))
        #expect(artifact.assetName.hasSuffix("-darwin-arm64"))
    }
}

@Test func instagramIsPinnedToTheVersionItsFlowsWereReadFrom() throws {
    let instagram = try BridgeCatalog.require(.instagram)
    #expect(instagram.credentialStyle == .cookies)
    #expect(instagram.runtimeKind == .goBinary)
    // Read from a live v0.2607.0 bridge: the flow is named for the network, not the step type.
    #expect(instagram.expectedLoginFlowIDs == ["instagram"])
    #expect(instagram.artifact?.assetName == "mautrix-instagram-darwin-arm64")
    #expect(instagram.senderLocalpart == "instagrambot")
}

@Test func everyBridgeCarriesALicenceCompatibleWithPallo() {
    // Pallo is AGPL-3.0-or-later; shipping a bridge under something else would be a licence
    // violation that nothing else in the build would catch.
    for descriptor in BridgeCatalog.all {
        #expect(descriptor.license == "AGPL-3.0-or-later", "\(descriptor.id) licence drifted")
    }
}
