import SwiftUI
import PalloFeatures

public struct RootView: View {
    @Bindable var model: PalloAppModel
    @State private var section: SidebarSection = .inbox

    public init(model: PalloAppModel) {
        self.model = model
    }

    private var selectedInboxID: InboxItem.ID? {
        switch model.detailSelection {
        case .empty: nil
        case let .personSummary(id): .person(id)
        case let .conversation(route): .conversation(route)
        }
    }

    private var selectedPersonID: String? {
        guard case let .personSummary(id) = model.detailSelection else { return nil }
        return id
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let message = model.healthBannerMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .accessibilityIdentifier("health-banner")
            }
            HStack(spacing: 0) {
                NavigationRailView(selection: $section)
                    .fixedSize(horizontal: true, vertical: false)
                Divider()
                sidebar
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                Divider()
                detail
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder private var sidebar: some View {
        switch section {
        case .inbox:
            InboxView(
                items: model.inboxItems,
                selectedID: selectedInboxID,
                onSelect: model.selectInboxItem
            )
        case .contacts:
            ContactsListView(
                people: model.people,
                items: model.inboxItems,
                selectedPersonID: selectedPersonID,
                onSelect: model.selectPerson
            )
        case .settings:
            AccountsListView(
                accounts: model.accounts,
                health: model.health,
                isConnected: model.isConnected
            )
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.detailSelection {
        case .empty:
            ContentUnavailableView(
                "Choose a conversation",
                systemImage: "message",
                description: Text("Pick someone from the list to see their messages.")
            )
        case let .personSummary(personID):
            ContactSummaryView(
                personName: model.inboxItems.first { $0.id == .person(personID) }?.title
                    ?? model.people.first { $0.id == personID }?.displayName
                    ?? "Contact",
                summaries: model.summaries(for: personID),
                onOpen: model.openConversation
            )
        case let .conversation(route):
            ConversationView(model: model, route: route)
                .id(route)
        }
    }
}
