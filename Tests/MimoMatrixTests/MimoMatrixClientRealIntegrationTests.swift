import Foundation
import Testing
@testable import MimoMatrix
@testable import MimoRuntime

/// Proves the whole Phase 3 login path against a real Synapse: bootstrap, register Mimo's own
/// Matrix account, log in through the Rust SDK, persist the session, and restore it on a second
/// client without registering again.
@Test(
    .enabled(if: ProcessInfo.processInfo.environment["MIMO_RUNTIME_PYTHON"] != nil),
    .timeLimit(.minutes(5))
)
func realMatrixClientRegistersLogsInAndRestoresItsSession() async throws {
    let pythonPath = try #require(ProcessInfo.processInfo.environment["MIMO_RUNTIME_PYTHON"])
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches", isDirectory: true)
        .appendingPathComponent("MimoMatrixReal-\(UUID().uuidString)", isDirectory: true)
    // The bootstrapper requires a user-only root; the default 0755 is rejected.
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = try RuntimePaths(root: root, profileName: "matrix-real")
    let service = RuntimeProfileService(
        paths: paths,
        packageRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    )
    _ = try await service.bootstrap(python: URL(fileURLWithPath: pythonPath))

    let keychain = MatrixKeychain(service: "org.mimo.tests.\(UUID().uuidString)")
    let store = MatrixClientStore(profile: paths, keychain: keychain)
    defer { try? store.destroy() }

    try await service.withRunningRuntime { _, context in
        let provisioner = try MatrixAccountProvisioner(
            baseURL: context.baseURL,
            serverName: context.serverName,
            registrationSecret: context.registrationSecret
        )

        // First connect: registers the account and logs in.
        let first = MimoMatrixClient(
            homeserverURL: context.baseURL,
            store: store,
            provisioner: provisioner
        )
        let session = try await first.connect()
        #expect(session.userID == "@mimo:\(context.serverName)")
        #expect(!session.accessToken.isEmpty)
        #expect(!session.deviceID.isEmpty)

        // The session must be on disk so a later launch can restore it.
        let saved = try #require(try store.loadSession())
        #expect(saved.userID == session.userID)
        #expect(saved.deviceID == session.deviceID)

        await first.disconnect()

        // Second connect on a fresh client must restore, keeping the same device identity rather
        // than registering or logging in again.
        let second = MimoMatrixClient(
            homeserverURL: context.baseURL,
            store: store,
            provisioner: provisioner
        )
        let restored = try await second.connect()
        #expect(restored.deviceID == session.deviceID)
        #expect(restored.accessToken == session.accessToken)
        await second.disconnect()
    }

    // The store passphrase lives in the Keychain, never beside the encrypted database.
    #expect(try keychain.passphrase(forAccount: store.keychainAccount) != nil)
    #expect(FileManager.default.fileExists(atPath: store.dataDirectory.path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MIMO_RUNTIME_PYTHON"] != nil))
func registeringTheSameAccountTwiceIsIdempotent() async throws {
    let pythonPath = try #require(ProcessInfo.processInfo.environment["MIMO_RUNTIME_PYTHON"])
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches", isDirectory: true)
        .appendingPathComponent("MimoMatrixIdem-\(UUID().uuidString)", isDirectory: true)
    // The bootstrapper requires a user-only root; the default 0755 is rejected.
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = try RuntimePaths(root: root, profileName: "matrix-idem")
    let service = RuntimeProfileService(
        paths: paths,
        packageRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    )
    _ = try await service.bootstrap(python: URL(fileURLWithPath: pythonPath))

    try await service.withRunningRuntime { _, context in
        let provisioner = try MatrixAccountProvisioner(
            baseURL: context.baseURL,
            serverName: context.serverName,
            registrationSecret: context.registrationSecret
        )
        // Break caught: a second launch that cannot tolerate M_USER_IN_USE can never start again.
        let first = try await provisioner.ensureRegistered()
        let second = try await provisioner.ensureRegistered()
        #expect(first == second)
        #expect(first.userID == "@mimo:\(context.serverName)")
    }
}
