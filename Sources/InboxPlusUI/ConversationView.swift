import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    /// One line of text plus the field's vertical padding.
    private static let singleLineFieldHeight: CGFloat = 32

    @Bindable var model: InboxPlusAppModel
    let route: ConversationRoute
    @State private var showsLinkSheet = false
    @State private var linkError: String?
    @State private var isDropTargeted = false
    @State private var composerFocusRequest = 0
    @Environment(\.inboxPlusTheme) private var theme

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

    private var isLoadingMessages: Bool {
        model.loadingMessageRoutes.contains(route)
    }

    private var scrollTargetID: String? {
        TranscriptPresentation.focusMessage(in: messages, highlightedID: highlightedMessageID)?.id
    }

    private var highlightedMessageID: String? {
        guard let highlighted = model.highlightedMessage, highlighted.route == route else { return nil }
        return highlighted.messageID
    }

    private var draft: String {
        model.draft(for: route)
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
        .onDrop(
            of: capabilities.acceptsAttachments ? [.fileURL, .image] : [],
            isTargeted: $isDropTargeted,
            perform: stageDropped
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.highlight, lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
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
        .onChange(of: route) {
            model.markConversationRead(route)
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
                let muted = model.isMuted(route)
                Button {
                    model.setMuted(!muted, for: route)
                } label: {
                    Image(systemName: muted ? "bell.slash.fill" : "bell")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(muted ? AnyShapeStyle(InboxPlusTheme.ink) : AnyShapeStyle(.secondary))
                .help(muted ? "Unmute notifications" : "Mute notifications")
                .accessibilityLabel(muted ? "Unmute conversation" : "Mute conversation")
                .accessibilityIdentifier("mute-conversation")
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
                Group {
                    if isLoadingMessages {
                        ProgressView("Loading messages…")
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("conversation-loading")
                    } else if model.failedMessageRoutes.contains(route) {
                        HStack {
                            Text("Messages couldn't load.")
                            Button("Retry") { model.loadRecentMessages(in: route) }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("conversation-load-failure")
                    } else {
                        RecentHistoryNotice(
                            isEmpty: messages.isEmpty,
                            link: model.conversations.first { $0.route == route }?.deepLink
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 4, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
                                composerFocusRequest += 1
                            },
                            onFailure: { linkError = $0 }
                        )
                    }
                    .id(message.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        message.id == highlightedMessageID ? theme.highlight.opacity(0.08) : Color.clear
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: scrollTargetID) { scrollToFocus(proxy, animated: !isLoadingMessages) }
            .onChange(of: isLoadingMessages) { _, loading in
                if !loading { scrollToFocus(proxy, animated: false) }
            }
            .onChange(of: route) { scrollToFocus(proxy, animated: false) }
            .onAppear { scrollToFocus(proxy, animated: false) }
        }
    }

    private var capabilities: ConversationCapabilities {
        model.capabilities(for: route)
    }

    private var stagedAttachments: [OutgoingAttachment] {
        model.stagedAttachments(for: route)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedAttachments.isEmpty
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
            // Bottom-aligned, so the buttons stay beside the line being typed as the field grows.
            HStack(alignment: .bottom, spacing: 10) {
                // Absent, not disabled, when the network cannot take attachments at all: an action
                // that can never work here has no business occupying the composer.
                if capabilities.acceptsAttachments {
                    Button(action: chooseAttachment) {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .frame(height: Self.singleLineFieldHeight)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Attach a file")
                    .accessibilityIdentifier("attach-file")
                }
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Message…")
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    ComposerTextEditor(
                        text: draft,
                        onTextChange: { model.setDraft($0, for: route) },
                        onSubmit: send,
                        onStage: capabilities.acceptsAttachments ? { stage($0) } : nil,
                        onCancel: { model.cancelReply(in: route) },
                        focusRequest: composerFocusRequest
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(height: Self.singleLineFieldHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? AnyShapeStyle(theme.highlight) : AnyShapeStyle(.tertiary))
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
        stage(.files(panel.urls))
    }

    /// Stops at the first file refused, as the open panel always has.
    private func stage(_ content: StageableContent) {
        let rejection = switch content {
        case let .files(urls):
            urls.lazy.compactMap { model.stageAttachment(at: $0, for: route) }.first
        case let .image(data, filename):
            model.stageAttachment(data, named: filename, for: route)
        }
        linkError = rejection?.message
    }

    private func stageDropped(_ providers: [NSItemProvider]) -> Bool {
        Task {
            for provider in providers {
                guard let content = await StageableContent.load(from: provider) else { continue }
                stage(content)
            }
        }
        return true
    }

    /// The message opened from search while there is one, so history loading around it does not
    /// pull the transcript away; otherwise the newest message.
    private func scrollToFocus(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let target = TranscriptPresentation.focusMessage(in: messages, highlightedID: highlightedMessageID) else { return }
        let anchor: UnitPoint = target.id == highlightedMessageID ? .center : .bottom
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target.id, anchor: anchor) }
        } else {
            proxy.scrollTo(target.id, anchor: anchor)
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

/// Inbox+ keeps only recent messages and never pages further back, so the top of a transcript
/// says so and points to the network's own app for the rest.
private struct RecentHistoryNotice: View {
    let isEmpty: Bool
    let link: VerifiedDeepLink?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 4) {
            Text(TranscriptPresentation.recentHistoryNotice(isEmpty: isEmpty))
            if let link {
                Text("·")
                    .accessibilityHidden(true)
                Button("Open in \(link.platform.accessibilityLabel)") { openURL(link.url) }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("open-conversation-in-app")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent-history-notice")
    }
}

/// Lines the reaction button up with the text bubble rather than the whole message, whose
/// reactions and timestamp sit below it. A message without text centres on its attachments.
private extension VerticalAlignment {
    enum MessageBody: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }

    static let messageBody = VerticalAlignment(MessageBody.self)
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
    @State private var isHovering = false
    @State private var showsReactionPicker = false
    @Environment(\.inboxPlusTheme) private var theme

    private var failureReason: String? {
        guard case let .failed(reason) = message.deliveryState else { return nil }
        return reason
    }

    private var showsBody: Bool {
        AttachmentFormatting.showsBody(of: message)
    }

    private var foreground: Color {
        message.isOutgoing ? theme.onAccent : InboxPlusTheme.ink
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
        HStack(alignment: .messageBody) {
            if message.isOutgoing {
                Spacer(minLength: 60)
                reactButton
            }
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
                            message.isOutgoing ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.quaternary),
                            in: .rect(cornerRadius: 12)
                        )
                        .textSelection(.enabled)
                        .alignmentGuide(.messageBody) { $0[VerticalAlignment.center] }
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
            if !message.isOutgoing {
                reactButton
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isOutgoing ? .trailing : .leading)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        // Combining would swallow the attachment's own controls — its play button and its
        // "Open in app" action have to stay reachable.
        .accessibilityElement(children: message.attachments.isEmpty ? .combine : .contain)
        .accessibilityLabel(MessageBubble.accessibilityLabel(for: message, senderName: senderName, quote: quote))
        .accessibilityActions {
            if model.canReact(to: message) {
                Button("React") { showsReactionPicker = true }
            }
        }
        .contextMenu { actions }
    }

    /// Appears while the pointer is over the message, as the reaction button does in other chat
    /// apps. It keeps its place while hidden, so a long bubble does not rewrap under the pointer.
    @ViewBuilder private var reactButton: some View {
        if model.canReact(to: message) {
            Button {
                showsReactionPicker = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.title3)
                    .frame(width: 26, height: 26)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("React")
            .opacity(isHovering || showsReactionPicker ? 1 : 0)
            // The bubble's own React action reaches the same picker without a hidden button
            // being announced on every message.
            .accessibilityHidden(true)
            .popover(isPresented: $showsReactionPicker) {
                ReactionPicker(reactions: message.reactions) { key in
                    showsReactionPicker = false
                    react(key)
                }
            }
        }
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
                            reaction.includesMe ? AnyShapeStyle(theme.highlight.opacity(0.18)) : AnyShapeStyle(.quaternary),
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
                Divider()
                Button("More…") { showsReactionPicker = true }
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
