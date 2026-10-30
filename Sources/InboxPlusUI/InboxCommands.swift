import SwiftUI

struct InboxCommandActions {
    var selectSection: (SidebarSection) -> Void
    var focusSearch: () -> Void
    var clearSearch: (() -> Void)?
    var nextConversation: (() -> Void)?
    var previousConversation: (() -> Void)?
    var toggleUnread: (() -> Void)?
    var isUnread: Bool
}

private struct InboxCommandActionsKey: FocusedValueKey {
    typealias Value = InboxCommandActions
}

extension FocusedValues {
    var inboxCommandActions: InboxCommandActions? {
        get { self[InboxCommandActionsKey.self] }
        set { self[InboxCommandActionsKey.self] = newValue }
    }
}

public struct InboxCommands: Commands {
    @FocusedValue(\.inboxCommandActions) private var actions

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.selectSection(.settings) }
                .keyboardShortcut(",")
                .disabled(actions == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Inbox") { actions?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
            // No Escape shortcut here: a menu key equivalent would fire wherever focus is, clearing
            // the search while someone presses Escape in the composer. The search field handles it.
            Button("Clear Inbox Search") { actions?.clearSearch?() }
                .disabled(actions?.clearSearch == nil)
        }
        CommandMenu("Navigate") {
            Button("Inbox") { actions?.selectSection(.inbox) }
                .keyboardShortcut("1")
                .disabled(actions == nil)
            Button("Contacts") { actions?.selectSection(.contacts) }
                .keyboardShortcut("2")
                .disabled(actions == nil)
            Button("Settings") { actions?.selectSection(.settings) }
                .keyboardShortcut("3")
                .disabled(actions == nil)
            Divider()
            Button("Next Conversation") { actions?.nextConversation?() }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                .disabled(actions?.nextConversation == nil)
            Button("Previous Conversation") { actions?.previousConversation?() }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
                .disabled(actions?.previousConversation == nil)
        }
        CommandMenu("Conversation") {
            Button(actions?.isUnread == true ? "Mark as Read" : "Mark as Unread") {
                actions?.toggleUnread?()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(actions?.toggleUnread == nil)
        }
        CommandGroup(replacing: .help) {
            Link("Inbox+ Help", destination: URL(string: "https://github.com/Tsha0/InboxPlus#readme")!)
        }
    }
}
