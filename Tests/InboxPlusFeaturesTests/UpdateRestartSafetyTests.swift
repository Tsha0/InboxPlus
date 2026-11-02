import Foundation
import InboxPlusCore
import InboxPlusGateway
import InboxPlusTestSupport
import Testing
@testable import InboxPlusFeatures

private actor SuspendedSendGateway: TextOnlyTestGateway {
    private var completion: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    func loadSnapshot() async throws -> MessagingSnapshot { .empty }
    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        hasStarted = true
        await withCheckedContinuation { completion = $0 }
        return SendReceipt(messageID: "sent", route: route, deliveryState: .acknowledged)
    }
    func finish() { completion?.resume(); completion = nil }
}

@MainActor
@Test func updateRestartWaitsForASendEvenAfterTheComposerWasCleared() async throws {
    let gateway = SuspendedSendGateway()
    let model = InboxPlusAppModel(gateway: gateway)
    let route = ConversationRoute(accountID: "account", conversationID: "conversation")
    model.setDraft("send me", for: route)
    let submission = model.captureDraft(to: route)
    let task = Task { try await model.sendDraft(submission) }
    let deadline = ContinuousClock().now.advanced(by: .seconds(5))
    while !(await gateway.hasStarted), ContinuousClock().now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await gateway.hasStarted)
    model.setDraft("", for: route)
    #expect(model.hasUnfinishedMessagingWork)
    await gateway.finish()
    try await task.value
    #expect(!model.hasUnfinishedMessagingWork)
}

@MainActor
@Test func updateRestartPreservesAnUnsentDraftByRefusingToQuit() {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: .empty))
    let route = ConversationRoute(accountID: "account", conversationID: "conversation")
    #expect(!model.hasUnfinishedMessagingWork)
    model.setDraft("A message I have not sent", for: route)
    #expect(model.hasUnfinishedMessagingWork)
    model.setDraft("  \n", for: route)
    #expect(!model.hasUnfinishedMessagingWork)
}

@MainActor
@Test func updateRestartRefusesADraftLeftInAConversationThatIsNoLongerOpen() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    defer { model.stop() }
    model.openConversation(Fixtures.instagramRoute)
    model.setDraft("Half a reply", for: Fixtures.instagramRoute)
    model.openConversation(Fixtures.telegramRoute)

    #expect(model.draft(for: Fixtures.telegramRoute).isEmpty)
    #expect(model.hasUnfinishedMessagingWork)
}

@MainActor
@Test func updateRestartRefusesStagedAttachments() async throws {
    let route = ConversationRoute(accountID: "instagram", conversationID: "c1")
    let snapshot = MessagingSnapshot(
        accounts: [.init(id: "instagram", platform: .instagram, displayName: "Instagram")],
        identities: [.init(id: "them", accountID: "instagram", displayName: "Maya")],
        conversations: [.init(id: "c1", accountID: "instagram", identityID: "them", title: "Maya",
                              latestActivity: Date(), unreadCount: 0, capabilities: .mediaCapable)],
        messagesByRoute: [:]
    )
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot))
    try await model.start()
    defer { model.stop() }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("update-draft-\(UUID()).txt")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("not yet sent".utf8).write(to: file)
    #expect(!model.hasUnfinishedMessagingWork)
    #expect(model.stageAttachment(at: file, for: route) == nil)
    #expect(model.hasUnfinishedMessagingWork)
    let staged = try #require(model.stagedAttachments(for: route).first)
    model.removeStagedAttachment(staged, for: route)
    #expect(!model.hasUnfinishedMessagingWork)
}

@MainActor
@Test func setupRefreshKeepsDraftsAttachmentsAndTheOpenConversation() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    defer { model.stop() }
    model.openConversation(Fixtures.instagramRoute)
    model.setDraft("Keep this reply", for: Fixtures.instagramRoute)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("setup-draft-\(UUID()).txt")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("unsent attachment".utf8).write(to: file)
    #expect(model.stageAttachment(at: file, for: Fixtures.instagramRoute) == nil)
    let staged = try #require(model.stagedAttachments(for: Fixtures.instagramRoute).first)
    try await model.refreshRuntime {}
    #expect(model.draft(for: Fixtures.instagramRoute) == "Keep this reply")
    #expect(model.stagedAttachments(for: Fixtures.instagramRoute) == [staged])
    #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))
    #expect(model.openRoute == Fixtures.instagramRoute)
    #expect(!model.isRefreshingRuntime)
    model.removeStagedAttachment(staged, for: Fixtures.instagramRoute)
}

@MainActor
@Test func setupRefreshWaitsForAnActiveSendAndBlocksNewSends() async throws {
    let gateway = SuspendedSendGateway()
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    defer { model.stop() }
    let route = ConversationRoute(accountID: "account", conversationID: "conversation")
    model.setDraft("Finish sending", for: route)
    let sending = Task { try await model.sendDraft(model.captureDraft(to: route)) }
    let deadline = ContinuousClock().now.advanced(by: .seconds(5))
    while !(await gateway.hasStarted), ContinuousClock().now < deadline { await Task.yield() }
    #expect(await gateway.hasStarted)
    let refresh = Task { try await model.refreshRuntime {} }
    while !model.isRefreshingRuntime, ContinuousClock().now < deadline { await Task.yield() }
    await #expect(throws: ReplyError.refreshingRuntime) {
        try await model.sendReply("Do not send during restart", to: route)
    }
    await gateway.finish()
    try await sending.value
    try await refresh.value
    #expect(!model.isRefreshingRuntime)
}

@MainActor
@Test func setupRefreshTimeoutLeavesTheSendAndDraftUntouched() async throws {
    let gateway = SuspendedSendGateway()
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    defer { model.stop() }
    let route = ConversationRoute(accountID: "account", conversationID: "conversation")
    model.setDraft("Keep sending", for: route)
    let sending = Task { try await model.sendDraft(model.captureDraft(to: route)) }
    let deadline = ContinuousClock().now.advanced(by: .seconds(5))
    while !(await gateway.hasStarted), ContinuousClock().now < deadline { await Task.yield() }
    await #expect(throws: (any Error).self) {
        try await model.refreshRuntime(timeout: .zero) { Issue.record("must not stop an active send") }
    }
    #expect(model.draft(for: route) == "Keep sending")
    #expect(!model.isRefreshingRuntime)
    await gateway.finish()
    try await sending.value
}
