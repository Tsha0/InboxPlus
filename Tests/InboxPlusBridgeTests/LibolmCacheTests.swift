import Foundation
import Testing
@testable import InboxPlusBridgeService

private actor LibolmBuildRecorder {
    private var count = 0
    func build(in workspace: URL) async throws -> URL {
        count += 1
        await Task.yield()
        let file = workspace.appendingPathComponent("built-libolm")
        try Data("verified pinned library".utf8).write(to: file)
        return file
    }
    func builds() -> Int { count }
}

private func libolmFixture() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/LibolmCacheTests-\(UUID().uuidString)")
}

@Test func concurrentBridgeInstallsReuseOneVerifiedLibolmBuild() async throws {
    let root = libolmFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = LibolmBuildRecorder()
    let provisioner = LibolmProvisioner(cacheRoot: root.appendingPathComponent("cache")) {
        try await recorder.build(in: $0)
    }
    async let first = provisioner.install(into: root.appendingPathComponent("instagram"))
    async let second = provisioner.install(into: root.appendingPathComponent("whatsapp"))
    let destinations = try await [first, second]
    #expect(await recorder.builds() == 1)
    for file in destinations {
        #expect(try Data(contentsOf: file) == Data("verified pinned library".utf8))
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
    }
}

@Test func tamperedLibolmCacheIsRebuiltAndInstalledCopiesAreVerified() async throws {
    let root = libolmFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = LibolmBuildRecorder()
    let cache = root.appendingPathComponent("cache")
    let provisioner = LibolmProvisioner(cacheRoot: cache) { try await recorder.build(in: $0) }
    let directory = root.appendingPathComponent("telegram")
    let installed = try await provisioner.install(into: directory)
    try Data("changed installed bytes".utf8).write(to: installed)
    _ = try await provisioner.install(into: directory)
    #expect(await recorder.builds() == 1)
    #expect(try Data(contentsOf: installed) == Data("verified pinned library".utf8))

    let cached = cache.appendingPathComponent(LibolmProvisioner.cacheKey)
        .appendingPathComponent(LibolmProvisioner.libraryName)
    try Data("changed cached bytes".utf8).write(to: cached)
    _ = try await provisioner.install(into: root.appendingPathComponent("another-bridge"))
    #expect(await recorder.builds() == 2)
    #expect(try Data(contentsOf: cached) == Data("verified pinned library".utf8))
}
