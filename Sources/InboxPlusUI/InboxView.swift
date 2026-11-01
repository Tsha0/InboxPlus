import SwiftUI
import InboxPlusCore
import InboxPlusFeatures

public struct InboxView: View {
    let items: [InboxItem]
    let hiddenItems: [InboxItem]
    let selectedID: InboxItem.ID?
    let onToggleFavourite: (InboxItem) -> Void
    let onAction: (InboxItem, InboxItemAction) -> Void
    let favouriteError: String?
    let onSelect: (InboxItem) -> Void
    @Binding private var showsUnreadOnly: Bool
    @Binding private var query: String
    let searchFocusRequest: UUID?
    @FocusState private var searchFocused: Bool
    @State private var showsHidden = false
    @Environment(\.openURL) private var openURL

    public init(
        items: [InboxItem],
        hiddenItems: [InboxItem] = [],
        query: Binding<String>,
        showsUnreadOnly: Binding<Bool>,
        searchFocusRequest: UUID?,
        selectedID: InboxItem.ID? = nil,
        favouriteError: String? = nil,
        onToggleFavourite: @escaping (InboxItem) -> Void = { _ in },
        onAction: @escaping (InboxItem, InboxItemAction) -> Void = { _, _ in },
        onSelect: @escaping (InboxItem) -> Void
    ) {
        self._showsUnreadOnly = showsUnreadOnly
        self._query = query
        self.searchFocusRequest = searchFocusRequest
        self.favouriteError = favouriteError
        self.onToggleFavourite = onToggleFavourite
        self.onAction = onAction
        self.items = items
        self.hiddenItems = hiddenItems
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    private var visibleItems: [InboxItem] {
        InboxProjector.filtered(showsHidden ? hiddenItems : items, query: query, unreadOnly: showsUnreadOnly)
    }

    private var unreadTotal: Int {
        items.reduce(0) { $0 + $1.unreadCount }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(showsHidden ? "Hidden" : "Inbox")
                    .font(.title2.bold())
                Spacer()
                if unreadTotal > 0 {
                    Text("\(unreadTotal)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(InboxPlusTheme.paper)
                        .background(InboxPlusTheme.ink, in: .capsule)
                        .accessibilityLabel("\(unreadTotal) unread in total")
                }
            }
            .padding(.horizontal)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("inbox-search")
                    .focused($searchFocused)
                    .onExitCommand { query = "" }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
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

            if let favouriteError {
                Text(favouriteError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: showsUnreadOnly ? "checkmark.circle" : "magnifyingglass"
                )
                .frame(maxHeight: .infinity)
            } else {
                List(visibleItems) { item in
                    HStack {
                        Button {
                            onSelect(item)
                        } label: {
                            row(for: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                        .accessibilityIdentifier("inbox-item-\(item.id.accessibilityIdentifier)")
                        Button {
                            onToggleFavourite(item)
                        } label: {
                            Image(systemName: item.isFavourite ? "star.fill" : "star")
                        }
                        .buttonStyle(.plain)
                        .help(item.isFavourite ? "Remove from favourites" : "Add to favourites")
                        .accessibilityLabel("\(item.isFavourite ? "Unfavourite" : "Favourite") \(item.title)")
                        .accessibilityIdentifier("inbox-favourite-\(item.id.accessibilityIdentifier)")
                    }
                    .selectedRowBackground(selectedID == item.id)
                    .contextMenu { actions(for: item) }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            if showsHidden || !hiddenItems.isEmpty {
                Button(showsHidden ? "Back to Inbox" : "\(hiddenItems.count) hidden") {
                    showsHidden.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 10)
                .accessibilityIdentifier("inbox-hidden-toggle")
            }
        }
        .onChange(of: searchFocusRequest, initial: true) { _, request in
            if request != nil { searchFocused = true }
        }
        .onChange(of: hiddenItems.isEmpty) { _, isEmpty in
            if isEmpty { showsHidden = false }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
        .accessibilityIdentifier("inboxplus-inbox")
    }

    private var emptyTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        if showsUnreadOnly { return "Nothing unread" }
        return showsHidden ? "Nothing hidden" : "Inbox is empty"
    }

    @ViewBuilder private func actions(for item: InboxItem) -> some View {
        Button(item.unreadCount > 0 ? "Mark as Read" : "Mark as Unread") {
            onAction(item, item.unreadCount > 0 ? .markRead : .markUnread)
        }
        if item.isMuted {
            Button("Unmute") { onAction(item, .unmute) }
        } else {
            Menu("Mute") {
                ForEach(MuteDuration.allCases, id: \.self) { duration in
                    Button(Self.label(for: duration)) { onAction(item, .mute(duration)) }
                }
            }
        }
        Button(item.isHidden ? "Show in Inbox" : "Hide") {
            onAction(item, item.isHidden ? .unhide : .hide)
        }
        Button(item.isFavourite ? "Remove from Favourites" : "Add to Favourites") {
            onToggleFavourite(item)
        }
        if !item.appLinks.isEmpty {
            Divider()
            ForEach(item.appLinks, id: \.self) { link in
                Button("Open in \(link.platform.accessibilityLabel)") { openURL(link.url) }
            }
        }
    }

    static func label(for duration: MuteDuration) -> String {
        switch duration {
        case .oneHour: "For 1 Hour"
        case .eightHours: "For 8 Hours"
        case .forever: "Forever"
        }
    }

    private func row(for item: InboxItem) -> some View {
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
                HStack(spacing: 4) {
                    Text(item.title)
                        .fontWeight(.semibold)
                    if item.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Muted")
                    }
                }
                Text(item.conversationSummaries.first?.latestPreview ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(RelativeTime.short(item.latestActivity))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.unreadCount > 0 {
                    Text("\(item.unreadCount)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(InboxPlusTheme.paper)
                        // A muted conversation still counts, but should not shout.
                        .background(item.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(InboxPlusTheme.ink), in: .capsule)
                        .accessibilityLabel("\(item.unreadCount) unread")
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
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
