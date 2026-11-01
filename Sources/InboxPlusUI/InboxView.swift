import SwiftUI
import InboxPlusCore
import InboxPlusFeatures

public struct InboxView: View {
    let items: [InboxItem]
    let messageMatches: [MessageSearchResult]
    let selectedID: InboxItem.ID?
    let highlightedMessage: MessageReference?
    let onToggleFavourite: (InboxItem) -> Void
    let favouriteError: String?
    let onSelect: (InboxItem) -> Void
    let onSelectMessage: (MessageReference) -> Void
    @Binding private var filter: InboxFilter
    @Binding private var query: String
    let searchFocusRequest: UUID?
    @FocusState private var searchFocused: Bool

    public init(
        items: [InboxItem],
        query: Binding<String>,
        filter: Binding<InboxFilter>,
        searchFocusRequest: UUID?,
        messageMatches: [MessageSearchResult] = [],
        selectedID: InboxItem.ID? = nil,
        highlightedMessage: MessageReference? = nil,
        favouriteError: String? = nil,
        onToggleFavourite: @escaping (InboxItem) -> Void = { _ in },
        onSelect: @escaping (InboxItem) -> Void,
        onSelectMessage: @escaping (MessageReference) -> Void = { _ in }
    ) {
        self._filter = filter
        self._query = query
        self.searchFocusRequest = searchFocusRequest
        self.messageMatches = messageMatches
        self.favouriteError = favouriteError
        self.onToggleFavourite = onToggleFavourite
        self.items = items
        self.selectedID = selectedID
        self.highlightedMessage = highlightedMessage
        self.onSelect = onSelect
        self.onSelectMessage = onSelectMessage
    }

    private var visibleItems: [InboxItem] {
        InboxProjector.filtered(items, query: query, filter: filter)
    }

    private var unreadTotal: Int {
        items.reduce(0) { $0 + $1.unreadCount }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A chosen network stays listed after its last conversation goes, so it can still be cleared.
    private var networks: [Platform] {
        let present = InboxProjector.platforms(in: items)
        guard let chosen = filter.platform, !present.contains(chosen) else { return present }
        return present + [chosen]
    }

    private var unknownSenders: [InboxItem] {
        items.filter(\.isFromUnknownSender)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inbox")
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
                filterButton("All", isSelected: filter.scope == .all) {
                    filter.scope = .all
                }
                filterButton("Unread", isSelected: filter.scope == .unread) {
                    filter.scope = .unread
                }
                if !unknownSenders.isEmpty || filter.scope == .unknownSenders {
                    filterButton(
                        "Unknown senders",
                        unreadCount: unknownSenders.reduce(0) { $0 + $1.unreadCount },
                        isSelected: filter.scope == .unknownSenders
                    ) {
                        filter.scope = .unknownSenders
                    }
                    .help("People who aren't in your Contacts and you haven't replied to")
                }
            }
            .padding(.horizontal)

            if networks.count > 1 || filter.platform != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(networks, id: \.self) { platform in
                            let isSelected = filter.platform == platform
                            filterButton(platform.accessibilityLabel, platform: platform, isSelected: isSelected) {
                                filter.platform = isSelected ? nil : platform
                            }
                            .help(isSelected ? "Show every network" : "Show only \(platform.accessibilityLabel)")
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if let favouriteError {
                Text(favouriteError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if visibleItems.isEmpty && messageMatches.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleItems) { item in
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
                    }
                    if !messageMatches.isEmpty {
                        Section("Messages") {
                            ForEach(messageMatches) { match in
                                messageRow(for: match)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .onChange(of: searchFocusRequest, initial: true) { _, request in
            if request != nil { searchFocused = true }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
        .accessibilityIdentifier("inboxplus-inbox")
    }

    private var emptyTitle: String {
        if isSearching { return "No matches" }
        switch filter.scope {
        case .all: return filter.platform.map { "No \($0.accessibilityLabel) conversations" } ?? "Inbox is empty"
        case .unread: return "Nothing unread"
        case .unknownSenders: return "No unknown senders"
        }
    }

    private var emptySymbol: String {
        switch filter.scope {
        case .all: "magnifyingglass"
        case .unread: "checkmark.circle"
        case .unknownSenders: "person.crop.circle.badge.questionmark"
        }
    }

    private func messageRow(for match: MessageSearchResult) -> some View {
        Button {
            onSelectMessage(match.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                PlatformBadge(platform: match.platform)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(match.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(RelativeTime.short(match.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(emphasizingQuery(in: match.snippet))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectedRowBackground(highlightedMessage == match.id)
        .accessibilityAddTraits(highlightedMessage == match.id ? .isSelected : [])
        .accessibilityIdentifier("inbox-message-\(match.id.route.accountID)-\(match.id.route.conversationID)-\(match.id.messageID)")
    }

    private func emphasizingQuery(in snippet: String) -> AttributedString {
        var text = AttributedString(snippet)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: query, options: .caseInsensitive) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
            text[range].foregroundColor = .primary
        }
        return text
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
                Text(item.title)
                    .fontWeight(.semibold)
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
                        .background(InboxPlusTheme.ink, in: .capsule)
                        .accessibilityLabel("\(item.unreadCount) unread")
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
    }

    private func filterButton(
        _ title: String,
        platform: Platform? = nil,
        unreadCount: Int = 0,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let platform {
                    PlatformBadge(platform: platform, size: 15)
                }
                Text(title)
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unreadCount > 0 ? "\(title), \(unreadCount) unread" : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
