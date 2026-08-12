import SwiftUI
import PalloFeatures

public struct InboxView: View {
    let items: [InboxItem]
    let onSelect: (InboxItem) -> Void
    @State private var showsUnreadOnly = false

    public init(items: [InboxItem], onSelect: @escaping (InboxItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    private var visibleItems: [InboxItem] {
        showsUnreadOnly ? items.filter { $0.unreadCount > 0 } : items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inbox")
                .font(.title2.bold())
                .padding(.horizontal)

            HStack(spacing: 6) {
                filterButton("All", isSelected: !showsUnreadOnly) {
                    showsUnreadOnly = false
                }
                filterButton("Unread", isSelected: showsUnreadOnly) {
                    showsUnreadOnly = true
                }
            }
            .padding(.horizontal)

            List(visibleItems) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 8) {
                        if let first = item.conversationSummaries.first {
                            PlatformBadge(platform: first.platform)
                        }
                        if item.conversationSummaries.count > 1 {
                            Text("+\(item.conversationSummaries.count - 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(
                                    "\(item.conversationSummaries.count - 1) additional network\(item.conversationSummaries.count == 2 ? "" : "s")"
                                )
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .fontWeight(.semibold)
                            Text(item.conversationSummaries.first?.latestPreview ?? "")
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.latestActivity, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.unreadCount > 0 {
                                Text("\(item.unreadCount)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(.blue, in: .capsule)
                                    .accessibilityLabel("\(item.unreadCount) unread")
                            }
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox-item-\(item.id.accessibilityIdentifier)")
            }
            .listStyle(.sidebar)
        }
        .padding(.top, 16)
        .accessibilityIdentifier("pallo-inbox")
    }

    private func filterButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
