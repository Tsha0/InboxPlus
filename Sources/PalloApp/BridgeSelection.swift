import Foundation
import PalloBridge
import PalloBridgeService
import PalloCore
import PalloRuntime
import PalloUI

/// Supplies the login session behind the account picker.
///
/// Preparing a bridge means downloading a checksum-pinned binary and registering an appservice with
/// the homeserver, which only makes sense against a running developer profile. Without one the app
/// offers no login session at all, and `RootView` says why rather than presenting a login that
/// could never complete.
enum BridgeSelection {
    static func makeProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BridgeLoginSessionProvider? {
        // Resolved the same way the gateway resolves it, including the single-prepared-profile
        // fallback: an app launched from Finder inherits no environment, and offering no login
        // while the very same launch is attached to a real account is indistinguishable from a bug.
        guard let profileName = GatewaySelection.resolveProfileName(environment: environment)
        else { return nil }

        return { @MainActor platform in
            let descriptor = try BridgeCatalog.require(platform)
            let root = try RuntimeProfileService.developerRuntimeRoot(environment: environment)
            let paths = try RuntimePaths(root: root, profileName: profileName)
            guard let state = try RuntimeProfileStore(paths: paths).load(),
                  let port = state.snapshot.loopbackPort
            else { throw GatewaySelectionError.profileNotRunning(profileName) }

            let runtime = BridgeRuntime(paths: paths)
            guard let record = try runtime.prepared(for: platform) else {
                throw BridgeSelectionError.notPrepared(
                    platform: platform,
                    bridgeID: descriptor.id,
                    profile: profileName
                )
            }
            // The homeserver takes a new port each session, so the config on disk may name the
            // previous one.
            try runtime.rebindToHomeserver(port: port)
            return try runtime.provisioningClient(for: record)
        }
    }
}

enum BridgeSelectionError: Error, CustomStringConvertible {
    case notPrepared(platform: Platform, bridgeID: String, profile: String)

    var description: String {
        switch self {
        case let .notPrepared(platform, bridgeID, profile):
            """
            The \(platform.accessibilityLabel) bridge is not installed for profile '\(profile)'. \
            Install and register it first, then restart the profile so the homeserver loads it:

              PalloRuntimeCLI bridge --profile \(profile) --action prepare --network \
            \(platform.rawValue)

            (bridge id: \(bridgeID))
            """
        }
    }
}
