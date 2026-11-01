import InboxPlusCore

/// Reads the status notices a bridge's bot posts in its management room, such as
/// "State update for Alex: TRANSIENT_DISCONNECT (…) not resolved after waiting 3 minutes".
///
/// The notice is the only place the bridge says its network connection dropped, so it becomes the
/// account's state instead of a message.
enum BridgeStateNotice {
    static func state(in body: String) -> NetworkConnectionState? {
        let prefix = "State update for "
        guard body.hasPrefix(prefix),
              let separator = body.range(of: ": ", range: body.index(body.startIndex, offsetBy: prefix.count)..<body.endIndex)
        else { return nil }
        let token = body[separator.upperBound...].prefix { $0.isUppercase || $0 == "_" }
        return NetworkConnectionState(rawValue: String(token))
    }
}
