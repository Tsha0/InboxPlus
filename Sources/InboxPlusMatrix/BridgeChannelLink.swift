import Foundation
import InboxPlusCore

/// Finds a bridged conversation in its network's own app, from the `m.bridge` state event the
/// bridge puts in every portal. Its `channel.id` is the network's own thread ID.
enum BridgeChannelLink {
    static let stateEventTypes: Set<String> = ["m.bridge", "uk.half-shot.bridge"]

    /// `state` is a room's state as `GET /rooms/{roomId}/state` returns it.
    static func link(inRoomState state: Data, platform: Platform) -> VerifiedDeepLink? {
        guard let events = try? JSONSerialization.jsonObject(with: state) as? [[String: Any]] else { return nil }
        for event in events {
            guard let type = event["type"] as? String, stateEventTypes.contains(type),
                  let content = event["content"] as? [String: Any],
                  let channel = content["channel"] as? [String: Any],
                  let id = channel["id"] as? String,
                  let link = link(toChannel: id, platform: platform)
            else { continue }
            return link
        }
        return nil
    }

    /// Only a numeric thread ID goes into a URL, so a bridge cannot point the link somewhere else.
    static func link(toChannel id: String, platform: Platform) -> VerifiedDeepLink? {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        switch platform {
        case .instagram:
            return try? DeepLinkVerifier.verify("https://www.instagram.com/direct/t/\(id)/", for: .instagram)
        default:
            return nil
        }
    }

    static func supports(_ platform: Platform) -> Bool {
        link(toChannel: "1", platform: platform) != nil
    }
}
