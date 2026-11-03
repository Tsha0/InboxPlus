import SwiftUI
import InboxPlusCore
import InboxPlusFeatures

public struct ContactSummaryView: View {
    let model: InboxPlusAppModel
    let personID: String
    let personName: String
    @State private var showsRename = false
    @State private var showsRemoval = false
    @State private var editedName = ""
    @State private var actionError: String?
    let summaries: [ConversationSummary]
    let onOpen: (ConversationRoute) -> Void
    @Environment(\.inboxPlusTheme) private var theme

    public init(
        model: InboxPlusAppModel,
        personID: String,
        personName: String,
        summaries: [ConversationSummary],
        onOpen: @escaping (ConversationRoute) -> Void
    ) {
        self.model = model
        self.personID = personID
        self.personName = personName
        self.summaries = summaries
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(personName)
                    .font(.title2.bold())
                Text(summaries.isEmpty
                     ? "No linked conversations yet"
                     : "\(summaries.count) conversation\(summaries.count == 1 ? "" : "s") across your networks")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Rename person…") {
                    editedName = personName
                    showsRename = true
                }
                Button("Remove person…", role: .destructive) { showsRemoval = true }
            }
            Text("Changes affect only Inbox+ grouping. Network conversations and messages are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let actionError { Text(actionError).foregroundStyle(.secondary) }

            if summaries.isEmpty {
                ContentUnavailableView(
                    "Nothing linked",
                    systemImage: "link",
                    description: Text("Open a conversation and choose “Link to person…” to group it here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(summaries) { summary in
                            card(for: summary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("contact-summary")
        .alert("Rename person", isPresented: $showsRename) {
            TextField("Name", text: $editedName)
            Button("Save") { attempt { try model.renamePerson(personID, displayName: editedName) } }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove this person and their Inbox+ links?", isPresented: $showsRemoval) {
            Button("Remove person", role: .destructive) { model.removePerson(personID) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Conversations and messages stay on their networks and in Inbox+ as separate chats.")
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func card(for summary: ConversationSummary) -> some View {
        let descriptor = ContactConversationCardDescriptor(
            route: summary.route,
            platform: summary.platform,
            title: summary.title,
            preview: summary.latestPreview,
            timestampDescription: summary.latestActivity.formatted(
                date: .abbreviated,
                time: .shortened
            ),
            unreadCount: summary.unreadCount
        )
        return Button {
            onOpen(descriptor.route)
        } label: {
            HStack(spacing: 12) {
                PlatformBadge(platform: descriptor.platform)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(descriptor.platform.accessibilityLabel)
                            .font(.subheadline.weight(.semibold))
                        Text(descriptor.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(descriptor.preview)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Text(descriptor.timestampDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                if descriptor.unreadCount > 0 {
                    Text("\(descriptor.unreadCount)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(theme.onAccent)
                        .background(theme.accent, in: .capsule)
                        .accessibilityLabel("\(descriptor.unreadCount) unread")
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .contextMenu {
            Button("Unlink conversation from this person") {
                attempt { try model.changePerson(for: summary.route, to: nil) }
            }
            Menu("Move conversation to person") {
                ForEach(model.people.filter { $0.id != personID }) { person in
                    Button(person.displayName) {
                        attempt { try model.changePerson(for: summary.route, to: person.id) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary)
        }
        .accessibilityLabel(descriptor.accessibilityLabel)
        .accessibilityIdentifier(
            "conversation-card-\(descriptor.route.accountID)-\(descriptor.route.conversationID)"
        )
    }
}
