import Foundation
import Testing
@testable import PalloRuntime

@Test func manifestRequiresPinnedSynapseAndPythonMinor() throws {
    let manifest = try RuntimeManifest.load(from: fixture("valid-runtime-manifest.json"))
    #expect(manifest.pythonMinor == "3.12")
    #expect(manifest.synapseVersion == "1.158.0")
}

private func fixture(_ name: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PalloRuntimeTests", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let url = directory.appendingPathComponent(name)
    let contents = """
    {"schemaVersion":1,"pythonMinor":"3.12","synapseVersion":"1.158.0","requirementsLockSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
    """
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}
