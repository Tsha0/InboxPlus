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

    /// What the app runs on. Media loading is paired with the gateway because both need the same
    /// authenticated client — fixtures get a controller with no loader, which simply never
    /// downloads rather than pretending to.
    struct Services {
        let gateway: any MessagingGateway
        let media: MediaController
    }

    @MainActor
    static func makeServices(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Services {
        guard let profileName = environment[profileEnvironmentKey], !profileName.isEmpty else {
            FileHandle.standardError.write(Data(
                "Pallo: no \(profileEnvironmentKey) set — running on demo fixtures.\n".utf8
            ))
            return Services(
                gateway: InMemoryMessagingGateway(seed: Fixtures.demoSnapshot),
                media: MediaController()
            )
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
            // Media lives beside the rest of the profile's private data and is bounded, so a long
            // history cannot fill the disk on its own.
            // Per profile, not per runtime root: two profiles are two separate installations and
            // must not share cached message content.
            let cacheDirectory = paths.profile.appendingPathComponent("media")
            let cache = try MediaCache(directory: cacheDirectory)
            let loader = MediaLoader(
                cache: cache,
                fetcher: MatrixMediaFetcher(client: client),
                freeSpace: VolumeFreeSpaceReporter(url: cacheDirectory)
            )

            return Services(
                gateway: MatrixMessagingGateway(
                    client: client,
                    invitePolicy: .forBridges(ids: bridgeIDs, serverName: state.serverName)
                ),
                media: MediaController(loader: loader)
            )
        } catch {
            // Surface the reason instead of silently substituting fake conversations.
            FileHandle.standardError.write(Data(
                "Pallo: could not attach to profile '\(profileName)': \(error)\n".utf8
            ))
            return Services(gateway: InMemoryMessagingGateway(seed: .empty), media: MediaController())
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
