import Foundation
import InboxPlusCore
import InboxPlusGateway
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp

private actor RuntimeConnections {
    private var generation = 0
    private(set) var operations: [String] = []

    func state() -> RuntimeProfileState {
        RuntimeProfileState(
            serverName: String(generation), registrationSecret: "test", launchExecutable: "/usr/bin/true",
            virtualEnvironmentPython: "/usr/bin/true", configurationFile: "fixture", snapshot: .stopped
        )
    }

    func restart() { operations.append("restart"); generation += 1 }
    func disconnected(_ generation: String) { operations.append("disconnect \(generation)") }
    func build(_ state: RuntimeProfileState) -> DeferredRuntimeGateway.Connection {
        operations.append("build \(state.serverName)")
        let account = ConnectedAccount(id: state.serverName, platform: .instagram, displayName: "Fixture")
        let source = InMemoryMessagingGateway(seed: MessagingSnapshot(
            accounts: [account], identities: [], conversations: [], messagesByRoute: [:]
        ))
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
