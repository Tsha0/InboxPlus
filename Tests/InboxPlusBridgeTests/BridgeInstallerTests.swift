import CryptoKit
import Foundation
import Testing
@testable import InboxPlusBridge
@testable import InboxPlusBridgeService
@testable import InboxPlusRuntime

private actor StubFetcher: BridgeArtifactFetching {
    private let status: Int
    private let body: Data
    private(set) var requestCount = 0

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }

    func fetch(_ url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> (status: Int, body: Data) {
        requestCount += 1
        progress(Int64(body.count / 2), Int64(body.count))
        progress(Int64(body.count), Int64(body.count))
        return (status, body)
    }

    func requests() -> Int { requestCount }
}

private func makePaths() throws -> (RuntimePaths, URL) {
    // Not the system temporary directory: it lives under `/var`, which is a symlink, and
    // `RuntimePaths` refuses symlinked ancestors by design.
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".build/InboxPlusBridgeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (try RuntimePaths(root: root, profileName: "test"), root)
}

private func descriptor(sha256: String) -> BridgeDescriptor {
    BridgeDescriptor(
        id: "testbridge",
        platform: .whatsApp,
        displayName: "Test",
        version: "v1.2.3",
        runtimeKind: .goBinary,
        credentialStyle: .qrCode,
        artifact: BridgeArtifact(
            assetName: "testbridge",
            sha256: sha256,
            downloadURL: URL(string: "https://example.com/testbridge")!
        ),
        expectedLoginFlowIDs: [],
        license: "AGPL-3.0-or-later",
        sourceURL: URL(string: "https://example.com")!
    )
}

@Test func averifiedBinaryIsInstalledExecutableAndUserOnly() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let bytes = Data("#!/bin/sh\necho hello\n".utf8)
    let installer = BridgeInstaller(
        paths: paths,
        fetcher: StubFetcher(body: bytes)
    )
    let installed = try await installer.install(descriptor(sha256: BridgeInstaller.hash(bytes)))

    #expect(FileManager.default.isExecutableFile(atPath: installed.executable.path))
    #expect(try Data(contentsOf: installed.executable) == bytes)
    let permissions = try FileManager.default
        .attributesOfItem(atPath: installed.executable.path)[.posixPermissions] as? Int
    #expect(permissions == 0o700, "an installed bridge must not be readable by other users")
    // The version is in the name so a bump cannot be mistaken for what is already on disk.
    #expect(installed.executable.lastPathComponent == "testbridge-v1.2.3")
}

@Test func aChecksumMismatchIsRejectedAndNothingIsWritten() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let expected = String(repeating: "a", count: 64)
    let installer = BridgeInstaller(
        paths: paths,
        fetcher: StubFetcher(body: Data("malicious".utf8))
    )
    let target = descriptor(sha256: expected)

    await #expect(throws: (any Error).self) { try await installer.install(target) }
    // The whole point: bytes that failed verification must never reach an executable path.
    #expect(!FileManager.default.fileExists(atPath: installer.executable(for: target).path))
    #expect(!installer.isInstalled(target))
}

@Test func aFailedDownloadIsReportedWithItsStatus() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = BridgeInstaller(
        paths: paths,
        fetcher: StubFetcher(status: 404, body: Data("not found".utf8))
    )
    await #expect(throws: BridgeInstallError.downloadFailed(bridge: "testbridge", status: 404)) {
        try await installer.install(descriptor(sha256: String(repeating: "b", count: 64)))
    }
}

@Test func anEmptyDownloadIsRejectedRatherThanInstalledAsAZeroByteBinary() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = BridgeInstaller(paths: paths, fetcher: StubFetcher(body: Data()))
    await #expect(throws: BridgeInstallError.emptyDownload("testbridge")) {
        try await installer.install(descriptor(sha256: BridgeInstaller.hash(Data())))
    }
}

@Test func reinstallingAnAlreadyVerifiedBinaryDoesNotDownloadAgain() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let bytes = Data("binary".utf8)
    let fetcher = StubFetcher(body: bytes)
    let installer = BridgeInstaller(paths: paths, fetcher: fetcher)
    let target = descriptor(sha256: BridgeInstaller.hash(bytes))

    try await installer.install(target)
    try await installer.install(target)
    #expect(await fetcher.requests() == 1)
}

@Test func aBinarySwappedAfterInstallationIsCaughtByVerification() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let bytes = Data("binary".utf8)
    let installer = BridgeInstaller(paths: paths, fetcher: StubFetcher(body: bytes))
    let target = descriptor(sha256: BridgeInstaller.hash(bytes))
    let installed = try await installer.install(target)

    try Data("tampered".utf8).write(to: installed.executable)
    #expect(throws: (any Error).self) { try installer.verify(target) }
}

@Test func aTamperedBinaryIsReplacedRatherThanTrustedByPath() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let bytes = Data("binary".utf8)
    let fetcher = StubFetcher(body: bytes)
    let installer = BridgeInstaller(paths: paths, fetcher: fetcher)
    let target = descriptor(sha256: BridgeInstaller.hash(bytes))
    let installed = try await installer.install(target)

    try Data("tampered".utf8).write(to: installed.executable)
    try await installer.install(target)

    #expect(try Data(contentsOf: installed.executable) == bytes)
    #expect(await fetcher.requests() == 2, "a tampered binary must be re-fetched, not reused")
}

@Test func aNativeAdapterHasNothingToInstall() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = BridgeInstaller(paths: paths, fetcher: StubFetcher(body: Data("x".utf8)))
    await #expect(throws: BridgeInstallError.nothingToInstall("imessage")) {
        try await installer.install(BridgeCatalog.iMessage)
    }
}

@Test func eachBridgeGetsItsOwnDirectoryUnderTheProfile() throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = BridgeInstaller(paths: paths)
    let instagram = installer.directory(for: BridgeCatalog.instagram)
    let whatsApp = installer.directory(for: BridgeCatalog.whatsApp)

    #expect(instagram != whatsApp)
    #expect(instagram.path.hasPrefix(paths.profile.path + "/"))
    #expect(whatsApp.path.hasPrefix(paths.profile.path + "/"))
}

private final class InstallProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BridgeSetupProgress] = []
    func record(_ value: BridgeSetupProgress) { lock.withLock { values.append(value) } }
    var recorded: [BridgeSetupProgress] { lock.withLock { values } }
}

@Test func bridgeInstallationReportsDownloadBytesBeforeVerification() async throws {
    let (paths, root) = try makePaths()
    defer { try? FileManager.default.removeItem(at: root) }
    let body = Data("verified bridge".utf8)
    let progress = InstallProgressLog()
    let installer = BridgeInstaller(paths: paths, fetcher: StubFetcher(body: body))
    try await installer.install(descriptor(sha256: BridgeInstaller.hash(body)), progress: { progress.record($0) })
    #expect(progress.recorded == [
        .downloading(received: 0, total: nil),
        .downloading(received: Int64(body.count / 2), total: Int64(body.count)),
        .downloading(received: Int64(body.count), total: Int64(body.count)),
        .verifying
    ])
}
