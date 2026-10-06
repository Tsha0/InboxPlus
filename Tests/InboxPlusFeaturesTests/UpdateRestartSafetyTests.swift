import Foundation
import InboxPlusCore
import InboxPlusGateway
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
    model.draft = "send me"
    let route = ConversationRoute(accountID: "account", conversationID: "conversation")
    let submission = model.captureDraft(to: route)
    let task = Task { try await model.sendDraft(submission) }
    let deadline = ContinuousClock().now.advanced(by: .seconds(5))
    while !(await gateway.hasStarted), ContinuousClock().now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await gateway.hasStarted)
    model.draft = ""
    #expect(model.hasUnfinishedMessagingWork)
    await gateway.finish()
    try await task.value
    #expect(!model.hasUnfinishedMessagingWork)
}

@MainActor
@Test func updateRestartPreservesAnUnsentDraftByRefusingToQuit() {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: .empty))
    #expect(!model.hasUnfinishedMessagingWork)
    model.draft = "A message I have not sent"
    #expect(model.hasUnfinishedMessagingWork)
    model.draft = "  \n"
    #expect(!model.hasUnfinishedMessagingWork)
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
