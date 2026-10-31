import InboxPlusCore

/// Carries out an account change beyond the screen: stopping a bridge, signing out of a network,
/// deleting what it stored.
///
/// Supplied by the app layer, which owns the runtime. Without one the model's own memory is all
/// there is to change, which is the whole truth for previews and fixtures.
public protocol AccountLifecycle: Sendable {
    /// Accounts the user disconnected, including in an earlier session.
    func disconnectedAccountIDs() async throws -> Set<String>
    /// Returns once the account has stopped delivering anything, and will stay stopped.
    func disconnect(_ account: ConnectedAccount) async throws
    func reconnect(_ account: ConnectedAccount) async throws -> AccountReconnection
    /// Returns only once the account's login, bridge and conversations are gone.
    func remove(_ account: ConnectedAccount) async throws -> AccountRemoval
}

public enum AccountReconnection: Equatable, Sendable {
    case reconnected
    /// The source is only opened at launch, so it comes back the next time Inbox+ opens.
    case onNextLaunch
}

public struct AccountRemoval: Equatable, Sendable {
    /// What could not be done, in words the user can act on. Empty when everything is gone.
    public var unfinished: [String]

    public init(unfinished: [String] = []) {
        self.unfinished = unfinished
    }
}

public extension ConnectedAccount {
    /// The local homeserver carries every bridged network, so it is never disconnected on its own.
    var canDisconnect: Bool { platform != .matrix }

    /// iMessage is read in place from the Messages app; Inbox+ keeps no copy of it to delete.
    var canRemove: Bool { platform != .matrix && platform != .iMessage }
}
