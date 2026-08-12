import SwiftUI
import PalloFeatures

public struct RootView: View {
    @Bindable var model: PalloAppModel

    public init(model: PalloAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let message = model.healthBannerMessage {
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .accessibilityIdentifier("health-banner")
            }
            HStack(spacing: 0) {
                NavigationRailView()
                Divider()
                InboxView(items: model.inboxItems, onSelect: model.selectInboxItem)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
                Divider()
                detail
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder private var detail: some View {
        switch model.detailSelection {
        case .empty:
            ContentUnavailableView("Choose a conversation", systemImage: "message")
        case let .personSummary(personID):
            ContactSummaryView(
                personName: model.inboxItems.first { $0.id == .person(personID) }?.title ?? "Contact",
                summaries: model.summaries(for: personID),
                onOpen: model.openConversation
            )
        case let .conversation(route):
            ConversationView(model: model, route: route)
        }
    }
}
