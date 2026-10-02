import Foundation
import Testing
@testable import InboxPlusApp
@testable import InboxPlusMatrix
import InboxPlusRuntime

@MainActor
@Test func launchWithoutPreparedProfileContainsNoDemoData() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxPlusEmptyLaunch-\(UUID().uuidString)")
    // A nonexistent, isolated root represents a fresh install without touching real profiles.
    let services = GatewaySelection.makeServices(environment: ["INBOXPLUS_RUNTIME_ROOT": root.path])
    let snapshot = try await services.gateway.loadSnapshot()
    #expect(snapshot.accounts.isEmpty)
    #expect(snapshot.conversations.isEmpty)
    #expect(snapshot.messagesByRoute.isEmpty)
    #expect(services.directory.people.isEmpty)
    #expect(services.directory.links.isEmpty)
}

@Test func bundledFreshInstallSelectsDefaultProfileWithoutManualSetup() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("InboxPlusSelection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let package = root.appendingPathComponent("package")
    let python = package.appendingPathComponent("Runtime/Python/bin/python3.12")
    try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("placeholder".utf8).write(to: python)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
    let environment = ["INBOXPLUS_RUNTIME_ROOT": root.appendingPathComponent("profiles").path,
                       "INBOXPLUS_RUNTIME_PACKAGE_ROOT": package.path]
    #expect(GatewaySelection.resolveProfileName(environment: environment) == "default")
    var named = environment
    named["INBOXPLUS_PROFILE"] = "work"
    #expect(GatewaySelection.resolveProfileName(environment: named) == "work")
}

@Test func messagingAndMediaUseTheSameMatrixClient() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MatrixServicesTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "wiring")
    let state = RuntimeProfileState(
        serverName: "inboxplus.localhost", registrationSecret: "test-only",
        launchExecutable: "/usr/bin/true", virtualEnvironmentPython: "/usr/bin/true",
        configurationFile: root.appendingPathComponent("unused.yaml").path,
        snapshot: try RuntimeSnapshot(
            phase: .healthy,
            processIdentity: ManagedProcessIdentity(executablePath: "/usr/bin/true", launchTimestamp: Date(),
                                                    processIdentifier: 1, startIdentityToken: "test-only"),
            loopbackPort: 18_008, restartCount: 0, lastHealthResult: "healthy",
            diagnosticLogDirectory: nil, lastError: nil
        )
    )
    let services = try GatewaySelection.makeMatrixServices(paths: paths, state: state, includeIMessage: false)
    let gateway = try #require(services.gateway as? MatrixMessagingGateway)
    let gatewayClient = await gateway.client
    #expect(gatewayClient === services.mediaFetcher.client)
    await gateway.stop()
}
