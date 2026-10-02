import Foundation
import Testing
@testable import InboxPlusBridgeService

@Test func shippedLibolmInstallsWithoutCMakeOrDownloads() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("InboxPlusLibolm-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("libolm.3.dylib")
    let contents = Data("test library".utf8)
    try contents.write(to: source)
    let provisioner = LibolmProvisioner(cmake: nil, bundledLibrary: source)
    let installed = try await provisioner.install(into: root.appendingPathComponent("bridge"))
    #expect(try Data(contentsOf: installed) == contents)
    #expect(try FileManager.default.attributesOfItem(atPath: installed.path)[.posixPermissions] as? Int == 0o600)

    try Data("altered installed bytes".utf8).write(to: installed)
    let repaired = try await provisioner.install(into: root.appendingPathComponent("bridge"))
    #expect(repaired == installed)
    #expect(try Data(contentsOf: repaired) == contents)
}
