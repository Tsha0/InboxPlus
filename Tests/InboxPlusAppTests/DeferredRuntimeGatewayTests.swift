import Foundation
import InboxPlusCore
import InboxPlusGateway
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp

private actor BuildGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    private(set) var waiting = false
    func wait() async {
        waiting = true
        if open { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}

private actor ResolvedGateway: MessagingGateway {
    private(set) var snapshots = 0
    private(set) var stops = 0
    func loadSnapshot() async throws -> MessagingSnapshot { snapshots += 1; return .empty }
    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: body, route: route, deliveryState: .pending)
    }
    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: attachment.filename, route: route, deliveryState: .pending)
    }
    func stop() async { stops += 1 }
}

private func deferredFixture(_ label: String) throws -> (RuntimePaths, URL, RuntimeProfileState) {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/DeferredGatewayTests-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let paths = try RuntimePaths(root: root, profileName: "test")
    let state = RuntimeProfileState(serverName: "inboxplus.localhost", registrationSecret: "test-only",
                                    launchExecutable: "/usr/bin/true", virtualEnvironmentPython: "/usr/bin/true",
                                    configurationFile: "unused", snapshot: .stopped)
    return (paths, root, state)
}

@Test func cancellingASharedResolutionWaiterDoesNotStartItsSnapshot() async throws {
    let (paths, root, state) = try deferredFixture("cancel")
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = BuildGate(), resolved = ResolvedGateway()
    let gateway = DeferredRuntimeGateway(paths: paths, profileName: "test",
                                          build: { _ in await gate.wait(); return resolved },
                                          ensureRunning: { state })
    let first = Task { try await gateway.loadSnapshot() }
    for _ in 0..<100 {
        if await gate.waiting { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let second = Task { try await gateway.loadSnapshot() }
    try await Task.sleep(for: .milliseconds(10))
    second.cancel()
    await gate.release()
    _ = try await first.value
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(await resolved.snapshots == 1)
    await gateway.stop()
}

@Test func stoppingDuringDeferredBuildStopsTheResultAndCancelsEveryWaiter() async throws {
    let (paths, root, state) = try deferredFixture("stop")
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = BuildGate(), resolved = ResolvedGateway()
    let gateway = DeferredRuntimeGateway(paths: paths, profileName: "test",
                                          build: { _ in await gate.wait(); return resolved },
                                          ensureRunning: { state })
    let first = Task { try await gateway.loadSnapshot() }
    for _ in 0..<100 {
        if await gate.waiting { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let second = Task { try await gateway.loadSnapshot() }
    try await Task.sleep(for: .milliseconds(10))
    let stop = Task { await gateway.stop() }
    try await Task.sleep(for: .milliseconds(10))
    await gate.release()
    await stop.value
    await #expect(throws: CancellationError.self) { try await first.value }
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(await resolved.snapshots == 0)
    #expect(await resolved.stops >= 1)
}
