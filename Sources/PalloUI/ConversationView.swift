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
    @FocusState private var composerFocused: Bool

    public init(model: PalloAppModel, route: ConversationRoute) {
        self.model = model
        self.route = route
    }

    private var summary: ConversationSummary? {
        model.inboxItems
            .flatMap(\.conversationSummaries)
            .first { $0.route == route }
    }

    private var messages: [Message] {
        model.messagesByRoute[route] ?? []
    }

    private var trimmedDraft: String {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .background(.background)
        .sheet(isPresented: $showsLinkSheet) {
            LinkPersonSheet(
                people: model.people,
                onSelect: { personID in
                    attemptLink { try model.linkOpenConversation(to: personID) }
                },
                onCreate: { name in
                    attemptLink { try model.createPersonAndLinkOpenConversation(displayName: name) }
                }
            )
        }
        .onAppear { composerFocused = true }
        .onChange(of: route) {
            model.markConversationRead(route)
            composerFocused = true
        }
        .accessibilityIdentifier("conversation-\(route.accountID)-\(route.conversationID)")
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let summary {
                    PlatformBadge(platform: summary.platform)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.title)
                            .font(.headline)
                        Text(summary.platform.accessibilityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Conversation")
                        .font(.headline)
                }
                Spacer()
                if model.personID(for: route) == nil {
                    Button("Link to person…") {
                        linkError = nil
                        showsLinkSheet = true
                    }
                }
            }
            if let linkError {
                Label(linkError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .onChange(of: messages.count) { scrollToLatest(proxy) }
            .onChange(of: route) { scrollToLatest(proxy, animated: false) }
            .onAppear { scrollToLatest(proxy, animated: false) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Message…", text: $model.draft)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
                    .accessibilityIdentifier("message-composer")
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(trimmedDraft.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                .disabled(trimmedDraft.isEmpty)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func send() {
        guard !trimmedDraft.isEmpty else { return }
        let submission = model.captureDraft(to: route)
        Task {
            do {
                try await model.sendDraft(submission)
            } catch {
                model.reportSendFailure(error, for: submission)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func attemptLink(_ action: () throws -> Void) {
        do {
            try action()
            linkError = nil
        } catch {
            linkError = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let message: Message

    private var failureReason: String? {
        guard case let .failed(reason) = message.deliveryState else { return nil }
        return reason
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                Text(message.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
                    .background(
                        message.isOutgoing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                        in: .rect(cornerRadius: 12)
                    )
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    if let failureReason {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(failureReason)
                            .foregroundStyle(.red)
                    } else {
                        if message.deliveryState == .pending {
                            Image(systemName: "clock")
                        }
                        Text(message.timestamp, style: .time)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !message.isOutgoing { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: message.isOutgoing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(message.isOutgoing ? "You" : "Them"): \(message.body)"
        )
    }
}
