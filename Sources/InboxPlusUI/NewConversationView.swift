import SwiftUI
import InboxPlusFeatures

struct NewConversationView: View {
    @Bindable var model: InboxPlusAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var accountID = ""
    @State private var recipient = ""
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
                    TextField("Email or international phone number (+…)", text: $recipient)
                        .textFieldStyle(.roundedBorder)
                        .disabled(opening)
                    Text("Recipient: \(recipient.isEmpty ? "Not selected" : recipient) · \(model.accounts.first { $0.id == accountID }?.platform.accessibilityLabel ?? "")")
                        .font(.callout)
                    Text("Continue opens the conversation. Nothing is sent until you write a message and press Send. Recipient availability is checked by Messages when you send.")
                        .font(.caption).foregroundStyle(.secondary)
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
        .padding(24).frame(width: 440)
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
            guard !accountID.isEmpty else { return }
            checking = true
            failure = nil
            let available = await model.canStartConversation(accountID: accountID)
            guard !Task.isCancelled else { return }
            supported = available
            checking = false
        }
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
