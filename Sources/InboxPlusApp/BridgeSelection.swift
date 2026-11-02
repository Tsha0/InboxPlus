import Foundation
import InboxPlusBridge
import InboxPlusBridgeService
import InboxPlusCore
import InboxPlusRuntime
import InboxPlusUI

enum BridgeSelection {
    static func makeProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        refreshRuntime: @escaping @MainActor (BridgeSetupProgressHandler) async throws -> Void,
        resumeInbox: @escaping @MainActor () async throws -> Void
    ) -> BridgeLoginSessionProvider? {
        guard let profileName = GatewaySelection.resolveProfileName(environment: environment)
        else { return nil }

        return { @MainActor platform, progress in
            guard BridgeCatalog.canConnect(platform) else {
                throw BridgeCatalogError.unsupportedPlatform(platform)
            }
            let descriptor = try BridgeCatalog.require(platform)
            let root = try RuntimeProfileService.developerRuntimeRoot(environment: environment)
            let paths = try RuntimePaths(root: root, profileName: profileName)
            progress(.checkingRuntime)
            let state = try await ManagedRuntime.shared.ensureRunning(paths: paths, profileName: profileName)
            guard let port = state.snapshot.loopbackPort
            else { throw GatewaySelectionError.profileNotRunning(profileName) }

            let runtime = BridgeRuntime(paths: paths)
            let existing = try runtime.prepared(for: platform)
            let record: PreparedBridge
            if let existing {
                record = existing
            } else {
                record = try await runtime.prepare(
                    descriptor, serverName: state.serverName, homeserverPort: port,
                    ownerUserID: "@inboxplus:\(state.serverName)", progress: progress
                )
            }
            try DisconnectedAccountStore(paths: paths).remove(record.bridgeID)
            try runtime.rebindToHomeserver(port: port)
            let result = try await loginPreparation(
                for: platform, profileName: profileName,
                session: runtime.provisioningClient(for: record),
                requiresRefresh: existing == nil,
                canRefresh: await ManagedRuntime.shared.canRefresh,
                refreshRuntime: { try await refreshRuntime(progress) }, progress: progress
            )
            if case .ready = result {
                progress(.syncing)
                try await resumeInbox()
            }
            return result
        }
    }

    @MainActor
    static func loginPreparation(
        for platform: Platform,
        profileName: String,
        session: BridgeProvisioningClient,
        requiresRefresh: Bool,
        canRefresh: Bool,
        readinessTimeout: Duration = .seconds(90),
        refreshRuntime: @MainActor () async throws -> Void,
        progress: BridgeSetupProgressHandler = { _ in }
    ) async throws -> BridgeLoginPreparation {
        if !requiresRefresh {
            progress(.checkingRuntime)
            if await waitUntilReady(session, timeout: readinessTimeout) { return .ready(session) }
        }
        guard canRefresh else {
            return .waitingForExternalRuntime(BridgeInstallOutcome(platform: platform, profile: profileName))
        }
        progress(.waitingForSends)
        try await refreshRuntime()
        progress(.waitingForBridge)
        guard await waitUntilReady(session, timeout: readinessTimeout) else {
            throw NSError(domain: "InboxPlus.Setup", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The \(platform.accessibilityLabel) connection did not become ready. Try connecting again. Your other connections and drafts are kept."
            ])
        }
        return .ready(session)
    }

    private static func waitUntilReady(_ session: BridgeProvisioningClient, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            if await session.isRunning() { return true }
            if Task.isCancelled { return false }
            guard clock.now < deadline else { return false }
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return false }
        } while true
    }
}
