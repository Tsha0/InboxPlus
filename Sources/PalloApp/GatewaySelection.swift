import Foundation
import PalloFeatures
import PalloGateway
import PalloBridge
import PalloBridgeService
import PalloIMessage
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
        /// Manually linked people. Fixture contacts belong only to the fixture gateway: a demo
        /// person sitting in Contacts beside real conversations, linked to identities that do not
        /// exist, is indistinguishable from a bug.
        let directory: ContactDirectory
    }

    @MainActor
    static func makeServices(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Services {
        guard let profileName = resolveProfileName(environment: environment) else {
            FileHandle.standardError.write(Data(
                ("Pallo: no \(profileEnvironmentKey) set and no prepared profile found — "
                    + "running on demo fixtures.\n").utf8
            ))
            return Services(
                gateway: InMemoryMessagingGateway(seed: Fixtures.demoSnapshot),
                media: MediaController(),
                directory: Fixtures.directory
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
            let prepared = (try? BridgeRuntime(paths: paths).prepared()) ?? []
            let bridgeIDs = prepared.map(\.bridgeID)
            // A portal room belongs to the network that created it, not to Matrix. The catalog is
            // what knows which network a bridge identifier means, and it lives here rather than in
            // the gateway so the Matrix layer keeps no opinion about bridges.
            let bridgeAccounts = prepared.compactMap { record -> BridgeAccountDescriptor? in
                guard let descriptor = BridgeCatalog.all.first(where: { $0.id == record.bridgeID })
                else { return nil }
                return BridgeAccountDescriptor(
                    bridgeID: record.bridgeID,
                    platform: descriptor.platform,
                    displayName: descriptor.displayName
                )
            }
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

            let matrix = MatrixMessagingGateway(
                client: client,
                invitePolicy: .forBridges(ids: bridgeIDs, serverName: state.serverName),
                bridgeAccounts: bridgeAccounts
            )

            // iMessage never reaches the homeserver, so it sits beside the Matrix gateway rather
            // than behind it. It is only added when the Messages database is actually readable:
            // offering a source that will throw on every read is worse than not offering it.
            var sources: [any MessagingGateway] = [matrix]
            if let imessage = makeIMessageGateway() { sources.append(imessage) }

            return Services(
                gateway: sources.count == 1 ? matrix : CompositeMessagingGateway(sources),
                media: MediaController(loader: loader),
                // Real accounts start with no linked people. Linking is something the user does.
                directory: ContactDirectory()
            )
        } catch {
            // Surface the reason instead of silently substituting fake conversations.
            FileHandle.standardError.write(Data(
                "Pallo: could not attach to profile '\(profileName)': \(error)\n".utf8
            ))
            return Services(
                gateway: InMemoryMessagingGateway(seed: .empty),
                media: MediaController(),
                directory: ContactDirectory()
            )
        }
    }
}

extension GatewaySelection {
    /// Decides which profile to attach to.
    ///
    /// The environment variable wins, but an app launched from Finder inherits no environment at
    /// all — so a bundled Pallo would always fall back to fixtures no matter how many real profiles
    /// existed. When exactly one profile is prepared, that is unambiguously the one meant, and
    /// using it is what makes a double-clicked app behave like the one started from a shell.
    ///
    /// With several profiles nothing is guessed: picking one at random would silently attach to the
    /// wrong account.
    static func resolveProfileName(environment: [String: String]) -> String? {
        if let named = environment[profileEnvironmentKey], !named.isEmpty { return named }

        guard let root = try? RuntimeProfileService.developerRuntimeRoot(environment: environment),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
              ) else { return nil }

        // Ask the store whether a profile is real rather than testing for a filename: the layout
        // is the store's business, and duplicating it here is how this silently stops working the
        // next time that file is renamed.
        let prepared = entries.filter { entry in
            guard let paths = try? RuntimePaths(root: root, profileName: entry.lastPathComponent),
                  let state = try? RuntimeProfileStore(paths: paths).load() else { return false }
            return state != nil
        }
        guard prepared.count == 1 else { return nil }
        return prepared[0].lastPathComponent
    }

    /// Opens the local Messages database, or explains why it could not.
    ///
    /// Full Disk Access is the usual reason and it cannot be requested programmatically, so the
    /// failure is written to stderr rather than swallowed — a silently missing iMessage looks like
    /// a bug in Pallo rather than a permission the user has not granted.
    static func makeIMessageGateway() -> IMessageGateway? {
        do {
            return IMessageGateway(store: try IMessageStore())
        } catch {
            FileHandle.standardError.write(Data(
                "Pallo: iMessage is not available: \(error)\n".utf8
            ))
            return nil
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
