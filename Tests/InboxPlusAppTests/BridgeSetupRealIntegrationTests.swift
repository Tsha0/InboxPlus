import Foundation
import InboxPlusBridge
import InboxPlusBridgeService
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusMatrix
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp

@MainActor
@Test(
    .enabled(if: ProcessInfo.processInfo.environment["INBOXPLUS_SETUP_RUNTIME_PACKAGE_ROOT"] != nil),
    .timeLimit(.minutes(5))
)
func realBridgeFirstInstallRefreshesServicesAndRestoresTheInboxWithoutRelaunching() async throws {
    let package = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["INBOXPLUS_SETUP_RUNTIME_PACKAGE_ROOT"]))
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches/InboxPlusSetup-\(UUID())", isDirectory: true)
    let paths = try RuntimePaths(root: root, profileName: "setup-\(UUID())")
    let runtime = ManagedRuntime(commandURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/InboxPlusRuntimeCLI"))
    var stopped = false
    defer { if stopped { try? FileManager.default.removeItem(at: root) } }
    let service = RuntimeProfileService(paths: paths, packageRoot: package)
    _ = try service.bootstrapBundled()
    let gateway = DeferredRuntimeGateway(
        ensureRunning: { try await runtime.ensureRunning(paths: paths, profileName: paths.profile.lastPathComponent) },
        restartRuntime: { try await runtime.refresh(paths: paths, profileName: paths.profile.lastPathComponent) },
        build: { state in
            let built = try GatewaySelection.makeMatrixGateway(paths: paths, state: state, makeIMessage: { _ in nil })
            return DeferredRuntimeGateway.Connection(gateway: built.gateway, disconnect: built.disconnect)
        }
    )
    let model = InboxPlusAppModel(gateway: gateway)
    defer { model.stop() }
    do {
        try await model.start()
        let first = try #require(try RuntimeProfileStore(paths: paths).load())
        let store = MatrixClientStore(profile: paths)
        let originalSession = try #require(try store.loadSession())
        let route = ConversationRoute(accountID: "instagram", conversationID: "unsent")
        model.setDraft("Unsent fixture reply", for: route)
        let bridges = BridgeRuntime(paths: paths, libolm: LibolmProvisioner(
            bundledLibrary: package.appendingPathComponent("Runtime/libolm.3.dylib")
        ))
        let record = try await bridges.prepare(
            BridgeCatalog.instagram, serverName: first.serverName,
            homeserverPort: try #require(first.snapshot.loopbackPort),
            ownerUserID: "@inboxplus:\(first.serverName)"
        )
        let preparation = try await BridgeSelection.loginPreparation(
            for: .instagram, profileName: paths.profile.lastPathComponent,
            session: bridges.provisioningClient(for: record),
            requiresRefresh: true, canRefresh: await runtime.canRefresh,
            refreshRuntime: { try await model.refreshRuntime { try await gateway.refreshRuntime() } }
        )
        guard case let .ready(session) = preparation else {
            throw NSError(domain: "InboxPlus.SetupTest", code: 1)
        }
        #expect(!(try await session.loginFlows()).isEmpty)
        let second = try #require(try RuntimeProfileStore(paths: paths).load())
        #expect(first.snapshot.processIdentity != second.snapshot.processIdentity)
        let restored = try #require(try store.loadSession())
        #expect(restored.deviceID == originalSession.deviceID)
        #expect(restored.accessToken == originalSession.accessToken)
        #expect(restored.homeserverURL == "http://127.0.0.1:\(try #require(second.snapshot.loopbackPort))")
        #expect(model.draft(for: route) == "Unsent fixture reply")
        #expect(model.health == .healthy)
        let observer = ManagedRuntime(commandURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/InboxPlusRuntimeCLI"))
        _ = try await observer.ensureRunning(paths: paths, profileName: paths.profile.lastPathComponent)
        #expect(await !observer.canRefresh)
        try await observer.stopForUpdate()
        #expect(await ManagedRuntime.homeserverAnswers(port: try #require(second.snapshot.loopbackPort)))
        try await runtime.refresh(paths: paths, profileName: paths.profile.lastPathComponent)
        #expect(try await gateway.runtimeChanged())
        try await model.refreshRuntime { try await gateway.refreshRuntime(restartServices: false) }
        #expect(try await !gateway.runtimeChanged())
        #expect(try store.loadSession()?.deviceID == originalSession.deviceID)
        #expect(model.draft(for: route) == "Unsent fixture reply")
        try await runtime.stopForUpdate(timeout: .seconds(90))
        stopped = true
        try store.destroy()
    } catch {
        try await runtime.stopForUpdate(timeout: .seconds(90))
        stopped = true
        throw error
    }
}
