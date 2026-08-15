import AppKit
import SwiftUI
import PalloCore
import PalloFeatures

/// Files chosen but not yet sent, each removable before it goes anywhere.
private struct StagedAttachmentsRow: View {
    let attachments: [OutgoingAttachment]
    let remove: (OutgoingAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.self) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: AttachmentFormatting.symbol(for: attachment.kind))
                            .foregroundStyle(.secondary)
                        Text(attachment.filename)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            remove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Remove \(attachment.filename)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.6), in: .capsule)
                }
            }
        }
        .accessibilityIdentifier("staged-attachments")
    }
}

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
                        MessageBubble(model: model, message: message)
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

    private var capabilities: ConversationCapabilities {
        model.capabilities(for: route)
    }

    private var stagedAttachments: [OutgoingAttachment] {
        model.stagedAttachments(for: route)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty || !stagedAttachments.isEmpty
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stagedAttachments.isEmpty {
                StagedAttachmentsRow(
                    attachments: stagedAttachments,
                    remove: { model.removeStagedAttachment($0, for: route) }
                )
            }
            HStack(spacing: 10) {
                // Absent, not disabled, when the network cannot take attachments at all: an action
                // that can never work here has no business occupying the composer.
                if capabilities.acceptsAttachments {
                    Button(action: chooseAttachment) {
                        Image(systemName: "paperclip")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Attach a file")
                    .accessibilityIdentifier("attach-file")
                }
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
                .foregroundStyle(canSend ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .disabled(!canSend)
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
        guard canSend else { return }
        let submission = model.captureDraft(to: route)
        Task {
            do {
                // Attachments first, so a caption typed alongside a photo arrives after it rather
                // than referring to something not yet on screen.
                try await model.sendStagedAttachments(to: route)
                try await model.sendDraft(submission)
            } catch {
                model.reportSendFailure(error, for: submission)
            }
        }
    }

    /// Uses the system's own open panel, so Pallo reads only what the user actually chose.
    private func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let rejection = model.stageAttachment(at: url, for: route) {
                linkError = rejection.message
                return
            }
        }
        linkError = nil
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
    @Bindable var model: PalloAppModel
    let message: Message

    private var failureReason: String? {
        guard case let .failed(reason) = message.deliveryState else { return nil }
        return reason
    }

    /// An attachment carries its own caption, so repeating the body above it would print the
    /// filename twice. Text alongside media is only shown when it says something different.
    private var showsBody: Bool {
        guard !message.attachments.isEmpty else { return true }
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !body.isEmpty && !message.attachments.contains { $0.displayName == body }
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                ForEach(message.attachments) { attachment in
                    AttachmentView(
                        model: model,
                        attachment: attachment,
                        accountID: message.route.accountID,
                        messageID: message.id
                    )
                }
                if showsBody {
                    Text(message.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
                        .background(
                            message.isOutgoing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                            in: .rect(cornerRadius: 12)
                        )
                        .textSelection(.enabled)
                }
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
        // Combining would swallow the attachment's own controls — its play button and its
        // "Open in app" action have to stay reachable.
        .accessibilityElement(children: message.attachments.isEmpty ? .combine : .contain)
        .accessibilityLabel(MessageBubble.accessibilityLabel(for: message))
    }

    static func accessibilityLabel(for message: Message) -> String {
        let speaker = message.isOutgoing ? "You" : "Them"
        guard !message.attachments.isEmpty else { return "\(speaker): \(message.body)" }
        let described = message.attachments
            .map(AttachmentFormatting.accessibilityLabel(for:))
            .joined(separator: ", ")
        return "\(speaker): \(described)"
    }
}
