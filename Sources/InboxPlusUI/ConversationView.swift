import AppKit
import SwiftUI
import InboxPlusCore
import InboxPlusFeatures

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

/// The message the next send will answer, with a way to stop answering it.
private struct ReplyTargetRow: View {
    let label: String
    let preview: String
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text(preview)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Cancel reply")
        }
        .accessibilityIdentifier("reply-target")
    }
}

private struct ReplyQuoteView: View {
    let quote: ReplyQuote

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tertiary)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if let sender = quote.sender {
                    Text(sender).font(.caption.weight(.semibold))
                }
                Text(quote.text)
                    .font(.caption)
                    .lineLimit(2)
            }
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replying to \(quote.accessibilityLabel)")
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
    @Bindable var model: InboxPlusAppModel
    let route: ConversationRoute
    @State private var showsLinkSheet = false
    @State private var linkError: String?
    @FocusState private var composerFocused: Bool

    public init(model: InboxPlusAppModel, route: ConversationRoute) {
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
                suggestedName: summary?.title ?? "",
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
                if model.canLinkConversation(route), model.personID(for: route) == nil {
                    Button("Link to person…") {
                        linkError = nil
                        showsLinkSheet = true
                    }
                }
            }
            if let linkError {
                Label(linkError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(InboxPlusTheme.ink)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            let namesSenders = TranscriptPresentation.namesSenders(in: messages)
            // Use the native list's bounded row layout. A LazyVStack combined with
            // scrollTo(bottom) can repeatedly invalidate its estimated heights on
            // macOS when switching chats, trapping the main thread in layout.
            List {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    let previous = index > 0 ? messages[index - 1] : nil
                    let next = index + 1 < messages.count ? messages[index + 1] : nil
                    VStack(spacing: 8) {
                        if TranscriptPresentation.startsDay(message, after: previous) {
                            Text(TranscriptPresentation.dayLabel(message.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .accessibilityAddTraits(.isHeader)
                        }
                        MessageBubble(
                            model: model, message: message,
                            senderName: TranscriptPresentation.senderName(message, identities: model.identities),
                            showsSender: namesSenders && !message.isOutgoing
                                && !TranscriptPresentation.sameRun(previous, message),
                            showsTimestamp: !TranscriptPresentation.sameRun(message, next),
                            quote: message.replyTo.map {
                                TranscriptPresentation.quote($0, in: messages, identities: model.identities)
                            },
                            onReply: {
                                model.beginReply(to: message)
                                composerFocused = true
                            },
                            onFailure: { linkError = $0 }
                        )
                    }
                    .id(message.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            if let target = model.replyTarget(in: route) {
                ReplyTargetRow(
                    label: TranscriptPresentation.replyingToLabel(target, identities: model.identities),
                    preview: target.body,
                    cancel: { model.cancelReply(in: route) }
                )
            }
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
                    .onExitCommand { model.cancelReply(in: route) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
                    .accessibilityIdentifier("message-composer")
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? AnyShapeStyle(InboxPlusTheme.ink) : AnyShapeStyle(.tertiary))
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
                    .foregroundStyle(InboxPlusTheme.ink)
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
                try await model.sendStagedAttachments(for: submission)
                try await model.sendDraft(submission)
            } catch {
                model.reportSendFailure(error, for: submission)
            }
        }
    }

    /// Uses the system's own open panel, so Inbox+ reads only what the user actually chose.
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
    @Bindable var model: InboxPlusAppModel
    let message: Message
    let senderName: String
    let showsSender: Bool
    let showsTimestamp: Bool
    let quote: ReplyQuote?
    let onReply: () -> Void
    let onFailure: (String) -> Void

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

    private var foreground: Color {
        message.isOutgoing ? InboxPlusTheme.paper : InboxPlusTheme.ink
    }

    /// Links are underlined and tinted to the bubble's text colour, so they stay legible on both
    /// bubble backgrounds.
    private var bodyText: Text {
        guard let markdown = message.markdownBody else { return Text(message.body) }
        var formatted = MessageFormatting.attributed(markdown: markdown)
        for run in formatted.runs where run.link != nil {
            formatted[run.range].swiftUI.underlineStyle = .single
        }
        return Text(formatted)
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                if showsSender {
                    Text(senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let quote {
                    ReplyQuoteView(quote: quote)
                }
                ForEach(message.attachments) { attachment in
                    AttachmentView(
                        model: model,
                        attachment: attachment,
                        accountID: message.route.accountID,
                        messageID: message.id
                    )
                }
                if showsBody {
                    bodyText
                        .tint(foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(foreground)
                        .background(
                            message.isOutgoing ? AnyShapeStyle(InboxPlusTheme.ink) : AnyShapeStyle(.quaternary),
                            in: .rect(cornerRadius: 12)
                        )
                        .textSelection(.enabled)
                }
                if !message.reactions.isEmpty {
                    reactionRow
                }
                HStack(spacing: 4) {
                    if let failureReason {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(InboxPlusTheme.ink)
                        Text(failureReason)
                            .foregroundStyle(InboxPlusTheme.ink)
                    } else if showsTimestamp || message.deliveryState == .pending {
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
        .accessibilityLabel(MessageBubble.accessibilityLabel(for: message, senderName: senderName, quote: quote))
        .contextMenu { actions }
    }

    /// Each pill toggles this account's own reaction, as choosing it from the menu does.
    private var reactionRow: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions, id: \.key) { reaction in
                Button { react(reaction.key) } label: {
                    Text(TranscriptPresentation.reactionLabel(reaction))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            reaction.includesMe ? AnyShapeStyle(InboxPlusTheme.ink.opacity(0.18)) : AnyShapeStyle(.quaternary),
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canReact(to: message))
                .help(reaction.includesMe ? "Remove your \(reaction.key)" : "React with \(reaction.key)")
            }
        }
    }

    /// Only what this network and this message allow: a reply or reaction that could only fail is
    /// not offered.
    @ViewBuilder private var actions: some View {
        let canReply = model.canReply(to: message)
        let canReact = model.canReact(to: message)
        if canReply {
            Button("Reply", action: onReply)
        }
        if canReact {
            Menu("React") {
                ForEach(TranscriptPresentation.reactionChoices(for: message), id: \.key) { choice in
                    Toggle(choice.key, isOn: Binding(get: { choice.includesMe }, set: { _ in react(choice.key) }))
                }
            }
        }
        if canReply || canReact {
            Divider()
        }
        if let text = TranscriptPresentation.copyableText(message) {
            Button("Copy Text") { copy(text) }
        }
        ForEach(message.attachments.filter { $0.deepLink != nil }) { attachment in
            Button(message.attachments.count == 1 ? "Copy Link" : "Copy Link to \(attachment.displayName)") {
                if let link = attachment.deepLink { copy(link.url.absoluteString) }
            }
        }
        ForEach(message.attachments.filter(\.isDownloadable)) { attachment in
            Button(message.attachments.count == 1 ? "Save Attachment…" : "Save \(attachment.displayName)…") {
                save(attachment)
            }
            .disabled(downloadedFile(of: attachment) == nil)
        }
    }

    private func react(_ key: String) {
        Task {
            do { try await model.toggleReaction(key, on: message) }
            catch { onFailure("Could not react: \(error.localizedDescription)") }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func downloadedFile(of attachment: MessageAttachment) -> URL? {
        guard case let .ready(url) = model.media.state(for: attachment) else { return nil }
        return url
    }

    /// The save panel has already asked before replacing an existing file.
    private func save(_ attachment: MessageAttachment) {
        guard let source = downloadedFile(of: attachment) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = AttachmentFormatting.suggestedFilename(for: attachment)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            onFailure("Could not save \(attachment.displayName): \(error.localizedDescription)")
        }
    }

    static func accessibilityLabel(for message: Message, senderName: String, quote: ReplyQuote?) -> String {
        let speaker = message.isOutgoing ? "You" : senderName
        let reply = quote.map { ", replying to \($0.accessibilityLabel)" } ?? ""
        let reactions = message.reactions.isEmpty ? ""
            : ", reactions: " + message.reactions.map(TranscriptPresentation.reactionLabel).joined(separator: ", ")
        guard !message.attachments.isEmpty else { return "\(speaker): \(message.body)\(reply)\(reactions)" }
        let described = message.attachments
            .map(AttachmentFormatting.accessibilityLabel(for:))
            .joined(separator: ", ")
        return "\(speaker): \(described)\(reply)\(reactions)"
    }
}
