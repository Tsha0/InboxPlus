import Testing
@testable import PalloCore
@testable import PalloGateway
@testable import PalloFeatures

private struct FailingGateway: MessagingGateway {
    struct Failure: Error {}

    func loadSnapshot() async throws -> MessagingSnapshot { throw Failure() }
    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt { throw Failure() }
}

@MainActor
@Test func startupFailureBecomesVisibleHealthState() async {
    let model = PalloAppModel(gateway: FailingGateway())
    do { try await model.start() } catch { model.reportStartupFailure(error) }
    guard case let .needsAttention(message) = model.health else {
        Issue.record("Expected needs-attention health")
        return
    }
    #expect(message.hasPrefix("Pallo could not start:"))
    #expect(model.healthBannerMessage?.hasPrefix("Pallo could not start:") == true)
}
