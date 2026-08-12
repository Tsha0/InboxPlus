import SwiftUI
import PalloCore
import PalloFeatures

public struct ConversationSendFailureDescriptor: Equatable, Sendable {
    public let route: ConversationRoute
    public let message: String

    public var accessibilityLabel: String {
        "Message could not be sent: \(message)"
    }

    public var accessibilityIdentifier: String {
        "send-error-\(route.accountID)-\(route.conversationID)"
    }

    public init(route: ConversationRoute, message: String) {
        self.route = route
        self.message = message
    }
}

public struct ConversationView: View {
    @Bindable var model: PalloAppModel
    let route: ConversationRoute
    @State private var showsLinkSheet = false
    @State private var linkError: String?

    public init(model: PalloAppModel, route: ConversationRoute) {
        self.model = model
        self.route = route
    }

    private var summary: ConversationSummary? {
        model.inboxItems
            .flatMap(\.conversationSummaries)
            .first { $0.route == route }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let summary {
                HStack(spacing: 10) {
                    PlatformBadge(platform: summary.platform)
                    Text(summary.title)
                        .fontWeight(.semibold)
                    Spacer()
                    if model.personID(for: route) == nil {
                        Button("Link to person…") {
                            linkError = nil
                            showsLinkSheet = true
                        }
                    }
                }
                .padding()
                if let linkError {
                    Text(linkError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                Divider()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messagesByRoute[route] ?? []) { message in
                        Text(message.body)
                            .padding(10)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Message…", text: $model.draft)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("message-composer")
                    Button {
                        let submission = model.captureDraft(to: route)
                        Task {
                            do {
                                try await model.sendDraft(submission)
                            } catch {
                                model.reportSendFailure(error, for: submission)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(
                        model.sendFailure(for: route) == nil ? "Send message" : "Retry message"
                    )
                    .accessibilityIdentifier("send-message")
                }
                if let message = model.sendFailure(for: route) {
                    let descriptor = ConversationSendFailureDescriptor(route: route, message: message)
                    Text(descriptor.accessibilityLabel)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel(descriptor.accessibilityLabel)
                        .accessibilityIdentifier(descriptor.accessibilityIdentifier)
                }
            }
            .padding(12)
        }
        .sheet(isPresented: $showsLinkSheet) {
            LinkPersonSheet(
                people: model.people,
                onSelect: { personID in
                    do {
                        try model.linkOpenConversation(to: personID)
                    } catch {
                        linkError = error.localizedDescription
                    }
                },
                onCreate: { name in
                    do {
                        try model.createPersonAndLinkOpenConversation(displayName: name)
                    } catch {
                        linkError = error.localizedDescription
                    }
                }
            )
        }
        .accessibilityIdentifier("conversation-\(route.accountID)-\(route.conversationID)")
    }
}
