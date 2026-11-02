import SwiftUI
import InboxPlusBridge
import InboxPlusCore

public struct BridgeInstallProgressView: View {
    private let platform: Platform
    private let progress: BridgeSetupProgress

    public init(platform: Platform, progress: BridgeSetupProgress) {
        self.platform = platform
        self.progress = progress
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Setting up \(platform.accessibilityLabel)")
                .font(.headline)
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
                    .accessibilityLabel("Bridge download")
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
            } else {
                ProgressView().controlSize(.large)
            }
            Text(progress.message)
                .font(.callout)
                .multilineTextAlignment(.center)
            Text("Keep Inbox+ open. Setup will continue automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 420, height: 220)
        .background(.background)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("bridge-install-progress")
    }
}
