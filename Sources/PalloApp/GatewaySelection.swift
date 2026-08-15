import Foundation
import PalloFeatures
import PalloGateway
import PalloBridgeService
import PalloMatrix
import PalloRuntime

/// Chooses which gateway the app runs on at launch.
///
/// Phase 3 has no onboarding yet, so the real Matrix runtime is selected explicitly by naming a
/// prepared developer profile. Without one the app runs on fixtures — and says so, rather than
/// presenting demo data as if it were live.
enum GatewaySelection {
    /// Set `PALLO_PROFILE=<name>` to run against a prepared, running developer profile.
    static let profileEnvironmentKey = "PALLO_PROFILE"

    static func makeGateway(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any MessagingGateway {
        guard let profileName = environment[profileEnvironmentKey], !profileName.isEmpty else {
            FileHandle.standardError.write(Data(
                "Pallo: no \(profileEnvironmentKey) set — running on demo fixtures.\n".utf8
            ))
            return InMemoryMessagingGateway(seed: Fixtures.demoSnapshot)
        }

        do {
            let root = try RuntimeProfileService.developerRuntimeRoot(environment: environment)
            let paths = try RuntimePaths(root: root, profileName: profileName)
            let state = try RuntimeProfileStore(paths: paths).load()
            guard let state, let port = state.snapshot.loopbackPort else {
                throw GatewaySelectionError.profileNotRunning(profileName)
            }

            let store = MatrixClientStore(profile: paths)
            let provisioner = try MatrixAccountProvisioner(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                serverName: state.serverName,
                registrationSecret: state.registrationSecret
            )
            let client = PalloMatrixClient(
                homeserverURL: URL(string: "http://127.0.0.1:\(port)")!,
                store: store,
                provisioner: provisioner
            )
            // Bridges invite this account into the portals they create, so the gateway needs to
            // know which local users are allowed to do that. Anything not in a prepared bridge's
            // own namespace is ignored.
            let bridgeIDs = ((try? BridgeRuntime(paths: paths).prepared()) ?? []).map(\.bridgeID)
            FileHandle.standardError.write(Data(
                """
                Pallo: using local Matrix runtime '\(profileName)' on port \(port)\
                \(bridgeIDs.isEmpty ? "" : " with bridges: \(bridgeIDs.joined(separator: ", "))").

                """.utf8
            ))
            return MatrixMessagingGateway(
                client: client,
                invitePolicy: .forBridges(ids: bridgeIDs, serverName: state.serverName)
            )
        } catch {
            // Surface the reason instead of silently substituting fake conversations.
            FileHandle.standardError.write(Data(
                "Pallo: could not attach to profile '\(profileName)': \(error)\n".utf8
            ))
            return InMemoryMessagingGateway(seed: .empty)
        }
    }
}

enum GatewaySelectionError: Error, CustomStringConvertible {
    case profileNotRunning(String)

    var description: String {
        switch self {
        case let .profileNotRunning(name):
            "profile '\(name)' is not running; start it with: PalloRuntimeCLI start --profile \(name)"
        }
    }
}
