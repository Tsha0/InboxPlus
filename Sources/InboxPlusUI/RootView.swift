import AppKit
import SwiftUI
import InboxPlusBridge
import InboxPlusCore
import InboxPlusFeatures

/// Opens a login session against the bridge for one network.
///
/// Supplied by the app layer, which owns the bridge processes. `InboxPlusUI` stays ignorant of how a
/// bridge is installed or supervised — it only renders the conversation the bridge asks for.
public typealias BridgeLoginSessionProvider =
    @MainActor (Platform, @escaping BridgeSetupProgressHandler) async throws -> BridgeLoginPreparation

public struct RootView: View {
    @Bindable var model: InboxPlusAppModel
    @Bindable var preferences: AppPreferences
    @State private var inboxQuery = ""
    @State private var inboxFilter = InboxFilter()
    @State private var searchFocusRequest: UUID?
    @State private var section: SidebarSection = .inbox
    @State private var accountFlow: AccountFlow?
    @State private var connectFailure: String?
    /// Informational, not a failure — reusing the failure alert would title good news as an error.
    @State private var connectNotice: ConnectNotice?
    @State private var accountFailure: AccountFailure?
    @State private var themePicks = 0
    @State private var setupProgress: BridgeSetupProgress = .checkingRuntime
    @State private var setupID = UUID()

    private let makeLoginSession: BridgeLoginSessionProvider?
    private let update: AppUpdatePresentation?
    private let onUpdate: () -> Void
    private let settings: AppSettingsServices

    enum AccountFlow: Identifiable {
        case picker
        case connectionWarning(Platform)
        case newConversation
        /// Downloading and registering a bridge this profile has never installed, which takes long
        /// enough that a picker sitting there unchanged would read as a dead click.
        case installing(Platform)
        case login(Platform, BridgeLoginController)
        case iMessagePermissions

        // The platform is carried alongside the controller because the controller is main-actor
        // isolated and `id` is not.
        var id: String {
            switch self {
            case .picker: "picker"
            case let .connectionWarning(platform): "warning-\(platform.rawValue)"
            case .newConversation: "new-conversation"
            case let .installing(platform): "installing-\(platform.rawValue)"
            case let .login(platform, _): "login-\(platform.rawValue)"
            case .iMessagePermissions: "imessage"
            }
        }
    }

    /// An alert that reports something worked, with its own title.
    struct ConnectNotice: Identifiable {
        let title: String
        let message: String
        var id: String { title }
    }

    /// An account change that did not happen, titled with what was attempted.
    struct AccountFailure {
        let title: String
        let message: String
    }

    public init(
        model: InboxPlusAppModel,
        preferences: AppPreferences,
        settings: AppSettingsServices = AppSettingsServices(),
        makeLoginSession: BridgeLoginSessionProvider? = nil,
        update: AppUpdatePresentation? = nil,
        onUpdate: @escaping () -> Void = {}
    ) {
        self.model = model
        self.preferences = preferences
        self.settings = settings
        self.makeLoginSession = makeLoginSession
        self.update = update
        self.onUpdate = onUpdate
    }

    private var theme: InboxPlusTheme {
        InboxPlusTheme(preferences.theme)
    }

    private var selectedInboxID: InboxItem.ID? {
        switch model.detailSelection {
        case .empty: nil
        case let .personSummary(id): .person(id)
        case let .conversation(route): .conversation(route)
        }
    }

    private var selectedPersonID: String? {
        guard case let .personSummary(id) = model.detailSelection else { return nil }
        return id
    }

    public var body: some View {
        VStack(spacing: 0) {
            if model.health == .starting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Preparing your inbox…")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.15))
                .background(.background)
                .accessibilityIdentifier("startup-progress")
            }
            if let message = model.healthBannerMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.15))
                    .background(.background)
                    .accessibilityIdentifier("health-banner")
            }
            HStack(spacing: 0) {
                NavigationRailView(selection: $section, update: update, onUpdate: onUpdate,
                                   canCompose: canStartNewConversation,
                                   onCompose: { accountFlow = .newConversation },
                                   themePicks: themePicks)
                    .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 0) {
                    if theme.titleBar == nil { Divider() }
                    sidebar
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                    Divider()
                    detail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
                // A themed window's own background is the title bar color, so panes that draw no
                // background of their own must not show it.
                .background(.background)
                // Under a themed bar the panes sit in a panel framed by the bar and the rail, as
                // Slack does, instead of running up into the title bar.
                .clipShape(.rect(topLeadingRadius: theme.titleBar == nil ? 0 : 10))
            }
            .clipped()
        }
        // macOS draws its own title bar material over the window's color, so the themed bar is
        // painted here, behind the title bar area as well as the rail.
        .background {
            if let titleBar = theme.titleBar {
                Color(nsColor: titleBar).ignoresSafeArea()
            }
        }
        .toolbarBackground(Color(nsColor: theme.titleBar ?? .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackgroundVisibility(theme.titleBar == nil ? .automatic : .visible, for: .windowToolbar)
        .toolbar(removing: theme.titleBar == nil ? nil : .title)
        .frame(minWidth: 900, minHeight: 600)
        .disabled(model.isPreparingForUpdate || model.isRefreshingRuntime)
        .focusedSceneValue(\.inboxCommandActions, commandActions)
        .environment(\.playsInstagramReels, preferences.playsInstagramReels)
        .environment(\.inboxPlusTheme, theme)
        .background(WindowTitleBar(color: theme.titleBar))
        .tint(theme.highlight)
        .accentColor(theme.highlight)
        .onChange(of: preferences.appearanceMode, initial: true) { _, mode in
            NSApplication.shared.appearance = mode.appearance
        }
        // The menu bar panel owns the connections overview; a Connect there lands here as a
        // pending request because the login sheet has to present from a window.
        .onChange(of: model.pendingConnectionRequest, initial: true) { _, platform in
            guard let platform else { return }
            model.clearConnectionRequest()
            startConnecting(platform)
        }
        // Settings fills the detail pane, so a conversation opened from elsewhere — a notification,
        // a new message — has to bring the inbox back to be seen.
        .onChange(of: model.detailSelection) { _, selection in
            if section == .settings, selection != .empty { section = .inbox }
        }
        .focusedSceneValue(\.newConversationAction, canStartNewConversation ? { accountFlow = .newConversation } : nil)
        .sheet(item: $accountFlow) { flow in
            switch flow {
            case .newConversation:
                NewConversationView(model: model)
            case .picker:
                AccountPickerView(
                    connectedPlatforms: model.platformsWithAccounts,
                    onSelect: startConnecting,
                    onCancel: { accountFlow = nil }
                )
            case let .connectionWarning(platform):
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect \(platform.accessibilityLabel)")
                        .font(.title2.bold())
                    Text("Using an unofficial client may permanently ban your account.")
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Learn about connection risks", destination: URL(string: "https://github.com/Tsha0/InboxPlus#networks")!)
                    HStack {
                        Button("Cancel") { accountFlow = nil }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Continue to sign in") { connectAfterWarning(platform) }
                    }
                }
                .padding(24)
                .frame(width: 440)
                .accessibilityIdentifier("connection-warning-\(platform.rawValue)")
            case let .installing(platform):
                BridgeInstallProgressView(platform: platform, progress: setupProgress)
            case let .login(platform, controller):
                LoginStepView(
                    controller: controller,
                    onFinished: { _ in finishConnecting(platform: platform) },
                    onCancel: { accountFlow = nil }
                )
            case .iMessagePermissions:
                IMessagePermissionsView(
                    onConnect: {
                        // There is nothing to sign in to. Inbox+ opens the Messages database at
                        // launch, so a grant made just now takes effect on the next launch — and
                        // adding an account here would invent one the gateway never produced.
                        accountFlow = nil
                        connectNotice = ConnectNotice(
                            title: "iMessage is connected",
                            message: """
                            iMessage is ready. Quit and reopen Inbox+ to load your conversations — \
                            macOS only applies Full Disk Access to a newly launched process.
                            """
                        )
                    },
                    onCancel: { accountFlow = nil }
                )
            }
        }
        .alert(
            "Could not start the bridge",
            isPresented: Binding(
                get: { connectFailure != nil },
                set: { if !$0 { connectFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) { connectFailure = nil }
        } message: {
            Text(connectFailure ?? "")
        }
        .alert(
            connectNotice?.title ?? "",
            isPresented: Binding(
                get: { connectNotice != nil },
                set: { if !$0 { connectNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) { connectNotice = nil }
        } message: {
            Text(connectNotice?.message ?? "")
        }
        .alert(
            accountFailure?.title ?? "",
            isPresented: Binding(
                get: { accountFailure != nil },
                set: { if !$0 { accountFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) { accountFailure = nil }
        } message: {
            Text(accountFailure?.message ?? "")
        }
    }

    private func startConnecting(_ platform: Platform) {
        if [.instagram, .facebookMessenger, .whatsApp, .telegram].contains(platform) {
            accountFlow = .connectionWarning(platform)
        } else {
            connectAfterWarning(platform)
        }
    }

    private func connectAfterWarning(_ platform: Platform) {
        // iMessage authenticates through macOS rather than a bridge process, so it takes the
        // permissions route instead of a login flow.
        guard platform != .iMessage else {
            accountFlow = .iMessagePermissions
            return
        }
        guard let makeLoginSession else {
            connectFailure = """
            Account setup is not ready. No unique messaging profile was selected. \
            Prepare a messaging profile and reopen Inbox+ before connecting a network.
            """
            accountFlow = nil
            return
        }
        Task { @MainActor in
            let id = UUID()
            setupID = id
            setupProgress = .checkingRuntime
            accountFlow = .installing(platform)
            do {
                switch try await makeLoginSession(platform, { progress in
                    Task { @MainActor in
                        guard setupID == id, progress.stage >= setupProgress.stage else { return }
                        setupProgress = progress
                    }
                }) {
                case let .ready(session):
                    accountFlow = .login(
                        platform,
                        BridgeLoginController(platform: platform, session: session)
                    )
                case let .waitingForExternalRuntime(outcome):
                    accountFlow = nil
                    connectNotice = ConnectNotice(
                        title: outcome.title,
                        message: outcome.message
                    )
                }
            } catch {
                connectFailure = String(describing: error)
                accountFlow = nil
            }
        }
    }

    private func finishConnecting(platform: Platform) {
        Task { @MainActor in
            setupProgress = .syncing
            accountFlow = .installing(platform)
            do {
                let bridge = try BridgeCatalog.require(platform)
                try model.addAccount(
                    ConnectedAccount(id: bridge.id, platform: bridge.platform, displayName: bridge.displayName)
                )
                try await model.refreshConversations()
            } catch {
                connectFailure = String(describing: error)
            }
            accountFlow = nil
        }
    }

    private var commandActions: InboxCommandActions? {
        guard accountFlow == nil, connectFailure == nil, connectNotice == nil, accountFailure == nil,
              !model.isPreparingForUpdate, !model.isRefreshingRuntime else { return nil }
        let canNavigate = !InboxProjector.filtered(model.listedInboxItems, query: inboxQuery, filter: inboxFilter).isEmpty
        let route = model.openRoute
        return InboxCommandActions(
            selectSection: { section = $0 },
            focusSearch: { section = .inbox; searchFocusRequest = UUID() },
            clearSearch: section == .inbox && !inboxQuery.isEmpty ? { inboxQuery = "" } : nil,
            nextConversation: canNavigate ? { section = .inbox; model.navigateConversation(forward: true, query: inboxQuery, filter: inboxFilter) } : nil,
            previousConversation: canNavigate ? { section = .inbox; model.navigateConversation(forward: false, query: inboxQuery, filter: inboxFilter) } : nil,
            toggleUnread: route.map { route in { model.toggleConversationUnread(route) } },
            isUnread: model.conversations.first { $0.route == route }?.unreadCount ?? 0 > 0
        )
    }

    private var canStartNewConversation: Bool {
        !model.isPreparingForUpdate
            && accountFlow == nil && connectFailure == nil && connectNotice == nil && accountFailure == nil
    }

    private func disconnect(_ account: ConnectedAccount) {
        Task { @MainActor in
            do { try await model.disconnect(accountID: account.id) }
            catch {
                accountFailure = AccountFailure(
                    title: "\(account.displayName) is still connected",
                    message: String(describing: error)
                )
            }
        }
    }

    private func reconnect(_ account: ConnectedAccount) {
        Task { @MainActor in
            do {
                guard try await model.reconnect(accountID: account.id) == .onNextLaunch else { return }
                connectNotice = ConnectNotice(
                    title: "\(account.displayName) is reconnected",
                    message: "Quit and reopen Inbox+ to load your \(account.displayName) conversations."
                )
            } catch {
                accountFailure = AccountFailure(
                    title: "\(account.displayName) is still disconnected",
                    message: String(describing: error)
                )
            }
        }
    }

    private func erase(_ account: ConnectedAccount) {
        Task { @MainActor in
            do {
                let removal = try await model.eraseAccount(accountID: account.id)
                guard !removal.unfinished.isEmpty else { return }
                connectNotice = ConnectNotice(
                    title: "\(account.displayName) was removed",
                    message: removal.unfinished.joined(separator: "\n\n")
                )
            } catch {
                accountFailure = AccountFailure(
                    title: "\(account.displayName) was not removed",
                    message: String(describing: error)
                )
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        switch section {
        case .inbox:
            InboxView(
                items: model.listedInboxItems,
                hiddenItems: model.hiddenInboxItems,
                query: $inboxQuery,
                filter: $inboxFilter,
                searchFocusRequest: searchFocusRequest,
                messageMatches: model.messageMatches(query: inboxQuery, filter: inboxFilter),
                selectedID: selectedInboxID,
                highlightedMessage: model.highlightedMessage,
                favouriteError: model.favouriteError ?? model.preferenceError ?? model.contactError,
                onToggleFavourite: model.toggleFavourite,
                onAction: { model.perform($1, on: $0) },
                unsentRoutes: model.routesWithDrafts.union(model.stagedAttachmentsByRoute.keys),
                onSelect: model.selectInboxItem,
                onSelectMessage: model.openMessage
            )
        case .contacts:
            ContactsListView(
                suggestions: model.suggestedContactLinks,
                onLink: model.acceptSuggestedContactLink,
                storageError: model.contactError,
                people: model.people,
                items: model.inboxItems,
                selectedPersonID: selectedPersonID,
                onSelect: model.selectPerson
            )
        case .settings:
            AccountsListView(
                accounts: model.userAccounts,
                health: model.health,
                isConnected: model.isConnected,
                isChanging: { model.accountIDsChanging.contains($0) },
                lastActivity: { model.lastActivity(for: $0) },
                signedInName: model.signedInName(for:),
                onAddAccount: { accountFlow = .picker },
                onDisconnect: disconnect,
                onReconnect: reconnect,
                onErase: erase
            )
        }
    }

    @ViewBuilder private var detail: some View {
        if section == .settings {
            PreferencesView(model: model, preferences: preferences, services: settings,
                            onThemePicked: { themePicks += 1 })
        } else {
            selectionDetail
        }
    }

    @ViewBuilder private var selectionDetail: some View {
        switch model.detailSelection {
        case .empty:
            ContentUnavailableView(
                "Choose a conversation",
                systemImage: "message",
                description: Text("Pick someone from the list to see their messages.")
            )
        case let .personSummary(personID):
            ContactSummaryView(
                model: model,
                personID: personID,
                personName: model.inboxItems.first { $0.id == .person(personID) }?.title
                    ?? model.people.first { $0.id == personID }?.displayName
                    ?? "Contact",
                summaries: model.summaries(for: personID),
                onOpen: model.openConversation
            )
        case let .conversation(route):
            ConversationView(model: model, route: route)
                .id(route)
        }
    }
}
