import SwiftUI
import PalloCore
import PalloFeatures

public struct ContactSummaryView: View {
    let personName: String
    let summaries: [ConversationSummary]
    let onOpen: (ConversationRoute) -> Void

    public init(
        personName: String,
        summaries: [ConversationSummary],
        onOpen: @escaping (ConversationRoute) -> Void
    ) {
        self.personName = personName
        self.summaries = summaries
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(personName)
                .font(.title2.bold())
            Text("Choose a conversation")
                .foregroundStyle(.secondary)
            ForEach(summaries) { summary in
                let descriptor = ContactConversationCardDescriptor(
                    route: summary.route,
                    platform: summary.platform,
                    title: summary.title,
                    preview: summary.latestPreview,
                    timestampDescription: summary.latestActivity.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ),
                    unreadCount: summary.unreadCount
                )
                Button {
                    onOpen(descriptor.route)
                } label: {
                    HStack(spacing: 12) {
                        PlatformBadge(platform: summary.platform)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.latestPreview)
                                .lineLimit(1)
                            Text(summary.latestActivity, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if summary.unreadCount > 0 {
                            Text("\(summary.unreadCount)")
                                .font(.caption.monospacedDigit())
                                .accessibilityLabel("\(summary.unreadCount) unread")
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary)
                }
                .accessibilityLabel(descriptor.accessibilityLabel)
                .accessibilityIdentifier(
                    "conversation-card-\(descriptor.route.accountID)-\(descriptor.route.conversationID)"
                )
            }
            Spacer()
        }
        .padding(20)
        .accessibilityIdentifier("contact-summary")
    }
}
