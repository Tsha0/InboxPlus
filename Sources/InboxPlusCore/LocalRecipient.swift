import Foundation

public struct LocalRecipient: Identifiable, Equatable, Sendable {
    public var id: String { name + "\n" + address }
    public let name: String
    public let address: String

    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && (name.localizedStandardContains(query) || address.localizedStandardContains(query))
    }

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public enum LocalRecipientSnapshot: Equatable, Sendable {
    case available([LocalRecipient])
    case accessUnavailable
    case failed
}
