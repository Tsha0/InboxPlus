import SwiftUI
import InboxPlusFeatures
import InboxPlusCore

struct NewConversationView: View {
    @Bindable var model: InboxPlusAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var accountID = ""
    @State private var recipient = ""
    @State private var query = ""
    @State private var selectedName: String?
    @State private var contacts: LocalRecipientSnapshot = .available([])
    @State private var contactRefreshID: UUID?
    private var loadingContacts: Bool { contactRefreshID != nil }
    @State private var supported = false
    @State private var checking = true
    @State private var opening = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New message").font(.title2.bold())
            if model.accounts.isEmpty {
                Text("Connect an account in Settings to start a conversation.")
            } else {
                Picker("Network", selection: $accountID) {
                    ForEach(model.accounts) { account in
                        Text("\(account.platform.accessibilityLabel) · \(account.displayName)").tag(account.id)
                            .disabled(!model.isConnected(account.id))
                    }
                }
                .disabled(opening)
                if checking {
                    ProgressView().controlSize(.small)
                } else if supported {
                    TextField("Name, email or international phone number (+…)", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .disabled(opening)
                        .onChange(of: query) {
                            selectedName = nil
                            let address = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            recipient = address.contains("@") || address.hasPrefix("+") ? address : ""
                        }
                    contactResults
                    Text("Recipient: \(selectedName.map { $0 + " · " } ?? "")\(recipient.isEmpty ? "Not selected" : recipient) · \(model.accounts.first { $0.id == accountID }?.platform.accessibilityLabel ?? "")")
                        .font(.callout)
                    Text("Continue opens the conversation. Nothing is sent until you write a message and press Send. Recipient availability is checked by Messages when you send.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Starting new conversations is not supported for this account yet. Start one in the network’s app, then return to Inbox+.")
                        .foregroundStyle(.secondary)
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    .disabled(opening)
                Button("Continue") {
                    opening = true
                    failure = nil
                    Task {
                        do {
                            try await model.startConversation(accountID: accountID, recipient: recipient)
                            dismiss()
                        } catch { failure = error.localizedDescription }
                        opening = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(checking || !supported || opening || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 480)
        .task {
            for account in model.accounts where model.isConnected(account.id) {
                if await model.canStartConversation(accountID: account.id) {
                    accountID = account.id
                    return
                }
            }
            accountID = model.accounts.first { model.isConnected($0.id) }?.id ?? ""
        }
        .task(id: accountID) {
            contactRefreshID = nil
            guard !accountID.isEmpty else { return }
            checking = true
            failure = nil
            query = ""
            recipient = ""
            selectedName = nil
            contacts = .available([])
            let available = await model.canStartConversation(accountID: accountID)
            guard !Task.isCancelled else { return }
            supported = available
            checking = false
            if available { await refreshContacts() }
        }
    }

    @ViewBuilder
    private var contactResults: some View {
        if model.accounts.first(where: { $0.id == accountID })?.platform == .iMessage {
            HStack {
                Text("Mac Contacts").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if loadingContacts { ProgressView().controlSize(.small) }
                Button("Refresh Contacts") { Task { await refreshContacts() } }
                    .disabled(loadingContacts || opening)
            }
            switch contacts {
            case .accessUnavailable:
                Text("Contacts access is unavailable. Allow Inbox+ in System Settings → Privacy & Security → Contacts, then refresh. You can still enter an email or international phone number.")
                    .font(.caption).foregroundStyle(.secondary)
            case .failed:
                Text("Contacts could not be loaded. Try refreshing, or enter an email or international phone number.")
                    .font(.caption).foregroundStyle(.secondary)
            case let .available(recipients):
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let matches = recipients.filter { $0.matches(query) }
                    if matches.isEmpty && !loadingContacts {
                        Text("No matching contacts. Enter an email or international phone number instead.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !matches.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(matches) { contact in
                                    Button {
                                        recipient = contact.address
                                        selectedName = contact.name
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(contact.name)
                                                Text(contact.address).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if selectedName == contact.name && recipient == contact.address {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(opening)
                                    .accessibilityLabel("Choose \(contact.name), \(contact.address)")
                                }
                            }
                        }
                        .frame(height: min(CGFloat(matches.count) * 52, 160))
                    }
                } else {
                    Text("Search by name. Contacts need an email or an international phone number (+…).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshContacts() async {
        let refreshID = UUID()
        contactRefreshID = refreshID
        defer {
            if contactRefreshID == refreshID { contactRefreshID = nil }
        }
        let selectedAccount = accountID
        let refreshed = await model.recipientContacts(accountID: selectedAccount)
        guard !Task.isCancelled, selectedAccount == accountID, contactRefreshID == refreshID else { return }
        contacts = refreshed
    }
}

private struct NewConversationActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    public var newConversationAction: (() -> Void)? {
        get { self[NewConversationActionKey.self] }
        set { self[NewConversationActionKey.self] = newValue }
    }
}
