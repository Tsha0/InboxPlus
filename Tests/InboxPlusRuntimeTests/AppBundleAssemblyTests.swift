import Foundation
import Testing

private func assemblyFixture() throws -> (root: URL, binaries: URL, app: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("InboxPlusAssembly-\(UUID().uuidString)")
    let binaries = root.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: binaries.appendingPathComponent("InboxPlus_InboxPlusUI.bundle"), withIntermediateDirectories: true)
    for name in ["InboxPlus", "InboxPlusRuntimeCLI"] {
        try Data(name.utf8).write(to: binaries.appendingPathComponent(name))
    }
    try Data([1]).write(to: binaries.appendingPathComponent("InboxPlus_InboxPlusUI.bundle/InboxPlusLogo.png"))
    let runtime = root.appendingPathComponent("Runtime")
    for name in ["Synapse/runtime-manifest.json", "Synapse/requirements.lock", "Python/bin/python3.12", "libolm.3.dylib"] {
        let file = runtime.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(name.utf8).write(to: file)
    }
    return (root, binaries, root.appendingPathComponent("Inbox+.app"))
}

private func assemble(binaries: URL, app: URL) throws -> Int32 {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [repo.appendingPathComponent("Scripts/assemble-app.sh").path, binaries.path, app.path, "0.5.0", app.deletingLastPathComponent().appendingPathComponent("Runtime").path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@Test func sharedBundleAssemblyIncludesEveryInstalledRuntimeInput() throws {
    let fixture = try assemblyFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    #expect(try assemble(binaries: fixture.binaries, app: fixture.app) == 0)
    for path in ["MacOS/InboxPlus", "MacOS/InboxPlusRuntimeCLI", "Resources/InboxPlus_InboxPlusUI.bundle/InboxPlusLogo.png",
                 "Resources/AppIcon.icns", "Resources/Runtime/Synapse/runtime-manifest.json",
                 "Resources/Runtime/Synapse/requirements.lock", "Resources/Runtime/Python/bin/python3.12", "Resources/Runtime/libolm.3.dylib"] {
        #expect(FileManager.default.fileExists(atPath: fixture.app.appendingPathComponent("Contents/\(path)").path))
    }
    let plist = try #require(try PropertyListSerialization.propertyList(
        from: Data(contentsOf: fixture.app.appendingPathComponent("Contents/Info.plist")), format: nil
    ) as? [String: Any])
    #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
    #expect(plist["CFBundleShortVersionString"] as? String == "0.5.0")
}

@Test func missingBundleInputLeavesAnExistingBundleIntact() throws {
    let fixture = try assemblyFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try FileManager.default.createDirectory(at: fixture.app, withIntermediateDirectories: true)
    let marker = fixture.app.appendingPathComponent("existing")
    try Data([7]).write(to: marker)
    try FileManager.default.removeItem(at: fixture.binaries.appendingPathComponent("InboxPlusRuntimeCLI"))
    #expect(try assemble(binaries: fixture.binaries, app: fixture.app) != 0)
    #expect(try Data(contentsOf: marker) == Data([7]))
}
