import MimoBridge
import MimoCore
import SwiftUI

/// Lets the user choose a network to connect.
///
/// All sixteen platforms are listed. The eleven Mimo cannot bridge yet are shown disabled with the
/// reason, because a roadmap presented as a product is how people end up believing a network works.
public struct AccountPickerView: View {
    private let connectedPlatforms: Set<Platform>
    private let onSelect: (Platform) -> Void
    private let onCancel: () -> Void

    public init(
        connectedPlatforms: Set<Platform>,
        onSelect: @escaping (Platform) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.connectedPlatforms = connectedPlatforms
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add an account")
                    .font(.title2.bold())
                Text("Pick the network you want to bring into Mimo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BridgeCatalog.pickerOrder, id: \.self) { platform in
                        tile(for: platform)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 520)
        .background(.background)
        .accessibilityIdentifier("account-picker")
    }

    @ViewBuilder
    private func tile(for platform: Platform) -> some View {
        let descriptor = BridgeCatalog.descriptor(for: platform)
        let isConnected = connectedPlatforms.contains(platform)
        // The one-account-per-platform rule is the app's, enforced in `AccountPolicy`; showing an
        // already-connected network as selectable would invite an error rather than prevent one.
        let isEnabled = descriptor != nil && !isConnected

        Button {
            onSelect(platform)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    PlatformBadge(platform: platform)
                    Text(platform.accessibilityLabel)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text(subtitle(platform: platform, descriptor: descriptor, isConnected: isConnected))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(isEnabled ? 0.3 : 0.12), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(subtitle(platform: platform, descriptor: descriptor, isConnected: isConnected))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(platform.accessibilityLabel)
        .accessibilityHint(subtitle(platform: platform, descriptor: descriptor, isConnected: isConnected))
        .accessibilityIdentifier("picker-\(platform.rawValue)")
    }

    /// An unavailable network says why it is unavailable. "Not yet available" invites the user to
    /// keep checking back for something that is blocked on a reason they could have been told.
    private func subtitle(platform: Platform, descriptor: BridgeDescriptor?, isConnected: Bool) -> String {
        if isConnected { return "Already connected" }
        guard let descriptor else {
            return BridgeCatalog.unavailabilityReason(for: platform) ?? "Not yet available in Mimo"
        }
        return descriptor.credentialStyle.summary
    }
}
