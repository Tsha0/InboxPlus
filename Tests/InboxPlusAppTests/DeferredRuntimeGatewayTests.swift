import Foundation
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp

private actor RuntimeConnections {
    private var generation = 0
    private var source: InMemoryMessagingGateway?
    private(set) var operations: [String] = []

    func state() -> RuntimeProfileState {
        RuntimeProfileState(
            serverName: String(generation), registrationSecret: "test", launchExecutable: "/usr/bin/true",
            virtualEnvironmentPython: "/usr/bin/true", configurationFile: "fixture", snapshot: .stopped
        )
    }

    func deliver() async throws -> SendReceipt? {
        try await source?.sendText("Fixture message", to: ConversationRoute(accountID: "0", conversationID: "fixture"))
    }

    func restart() { operations.append("restart"); generation += 1 }
    func disconnected(_ generation: String) { operations.append("disconnect \(generation)") }
    func build(_ state: RuntimeProfileState) -> DeferredRuntimeGateway.Connection {
        operations.append("build \(state.serverName)")
        let account = ConnectedAccount(id: state.serverName, platform: .instagram, displayName: "Fixture")
        let source = InMemoryMessagingGateway(seed: MessagingSnapshot(
            accounts: [account], identities: [], conversations: [], messagesByRoute: [:]
        ))
        self.source = source
        return DeferredRuntimeGateway.Connection(gateway: source, disconnect: { await self.disconnected(state.serverName) })
    }
}

@Test func runtimeRefreshDisconnectsTheOldClientAndRebuildsBeforeServingTheInbox() async throws {
    let connections = RuntimeConnections()
    let gateway = DeferredRuntimeGateway(
        ensureRunning: { await connections.state() }, restartRuntime: { await connections.restart() },
        build: { await connections.build($0) }
    )
    #expect(try await gateway.loadSnapshot().accounts.map(\.id) == ["0"])
    try await gateway.refreshRuntime()
    #expect(try await gateway.loadSnapshot().accounts.map(\.id) == ["1"])
    _ = try await gateway.loadSnapshot()
    #expect(await connections.operations == ["build 0", "disconnect 0", "restart", "build 1"])
}

@Test func anExternallyRestartedRuntimeReconnectsWithoutBeingRestartedAgain() async throws {
    let connections = RuntimeConnections()
    let gateway = DeferredRuntimeGateway(
        ensureRunning: { await connections.state() }, restartRuntime: { Issue.record("external runtime was restarted") },
        build: { await connections.build($0) }
    )
    _ = try await gateway.loadSnapshot()
    #expect(try await !gateway.runtimeChanged())
    await connections.restart()
    #expect(try await gateway.runtimeChanged())
    try await gateway.refreshRuntime(restartServices: false)
    #expect(try await gateway.loadSnapshot().accounts.map(\.id) == ["1"])
    #expect(try await !gateway.runtimeChanged())
    #expect(await connections.operations == ["build 0", "restart", "disconnect 0", "build 1"])
}

@MainActor
@Test func refusingAnExternalRuntimeRestartKeepsInboxEventsConnected() async throws {
    let connections = RuntimeConnections()
    let gateway = DeferredRuntimeGateway(
        ensureRunning: { await connections.state() }, restartRuntime: { await connections.restart() },
        build: { await connections.build($0) }
    )
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    defer { model.stop() }
    let runtime = ManagedRuntime(commandURL: URL(fileURLWithPath: "/usr/bin/true"))
    await #expect(throws: (any Error).self) {
        try await GatewaySelection.restartRuntime(gateway: gateway, model: model, runtime: runtime)
    }
    #expect(await connections.operations == ["build 0"])
    #expect(model.health == .healthy)
    #expect(!model.isRefreshingRuntime)
    let receipt = try #require(try await connections.deliver())
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.messagesByRoute[receipt.route]?.contains(where: { $0.id == receipt.messageID }) != true,
          ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.messagesByRoute[receipt.route]?.contains { $0.id == receipt.messageID } == true)
}
