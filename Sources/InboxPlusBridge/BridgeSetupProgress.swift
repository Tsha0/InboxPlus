public enum BridgeSetupProgress: Sendable, Equatable {
    case checkingRuntime
    case downloading(received: Int64, total: Int64?)
    case verifying
    case configuring
    case waitingForSends
    case restarting
    case waitingForBridge
    case syncing

    public var stage: Int {
        switch self {
        case .checkingRuntime: 0
        case .downloading: 1
        case .verifying: 2
        case .configuring: 3
        case .waitingForSends: 4
        case .restarting: 5
        case .waitingForBridge: 6
        case .syncing: 7
        }
    }

    public var message: String {
        switch self {
        case .checkingRuntime: "Preparing local services…"
        case .downloading: "Downloading the bridge…"
        case .verifying: "Verifying the bridge…"
        case .configuring: "Installing and registering the bridge…"
        case .waitingForSends: "Waiting for pending messages to finish…"
        case .restarting: "Restarting local services. Your drafts stay here…"
        case .waitingForBridge: "Waiting for the connection to become ready…"
        case .syncing: "Syncing your conversations…"
        }
    }

    public var fractionCompleted: Double? {
        guard case let .downloading(received, total) = self, let total, total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }
}

public typealias BridgeSetupProgressHandler = @Sendable (BridgeSetupProgress) -> Void
