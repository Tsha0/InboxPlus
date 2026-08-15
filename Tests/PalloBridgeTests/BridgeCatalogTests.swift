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
    #expect(throws: BridgeCatalogError.unsupportedPlatform(.discord)) {
        try BridgeCatalog.require(.discord)
    }
    #expect(BridgeCatalogError.unsupportedPlatform(.discord).description.contains("Discord"))
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
