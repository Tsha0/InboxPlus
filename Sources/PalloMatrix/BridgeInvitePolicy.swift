import Foundation

/// Decides which room invitations Pallo may accept on the user's behalf.
///
/// A bridge does not put you in a conversation; it creates a portal room and *invites* you, so an
/// unaccepted invite is an invisible conversation. Accepting automatically is therefore necessary —
/// but accepting anything at all would mean any local account could put a room in someone's inbox.
/// Only users inside a prepared bridge's own namespace are trusted, and the namespace is derived
/// from the bridge identifier rather than supplied as free text.
public struct BridgeInvitePolicy: Sendable, Equatable {
    /// Localpart prefixes that may invite, e.g. `instagram_` for ghosts and `instagrambot` for the
    /// bridge's own bot.
    public let trustedLocalpartPrefixes: [String]
    public let serverName: String

    public init(trustedLocalpartPrefixes: [String], serverName: String) {
        self.trustedLocalpartPrefixes = trustedLocalpartPrefixes
        self.serverName = serverName
    }

    /// Trusts nothing. The default, so a profile with no bridges behaves exactly as it did before.
    public static let trustingNobody = BridgeInvitePolicy(
        trustedLocalpartPrefixes: [],
        serverName: ""
    )

    /// The namespace a mautrix bridge claims: `@<id>_*` ghosts plus the `@<id>bot` bot.
    public static func forBridges(ids: [String], serverName: String) -> BridgeInvitePolicy {
        BridgeInvitePolicy(
            trustedLocalpartPrefixes: ids.flatMap { ["\($0)_", "\($0)bot"] },
            serverName: serverName
        )
    }

    public func trusts(inviterUserID: String) -> Bool {
        guard !trustedLocalpartPrefixes.isEmpty else { return false }
        guard inviterUserID.hasPrefix("@") else { return false }
        guard let colon = inviterUserID.firstIndex(of: ":") else { return false }

        let localpart = String(inviterUserID[inviterUserID.index(after: inviterUserID.startIndex)..<colon])
        let host = String(inviterUserID[inviterUserID.index(after: colon)...])
        // The homeserver is loopback-only and never federates, but pinning the server name keeps
        // the rule true rather than true-by-accident.
        guard host == serverName else { return false }
        return trustedLocalpartPrefixes.contains { localpart.hasPrefix($0) }
    }
}
