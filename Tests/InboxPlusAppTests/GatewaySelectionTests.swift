import Foundation
import Testing
@testable import InboxPlusApp

@MainActor
@Test func launchWithoutPreparedProfileContainsNoDemoData() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxPlusEmptyLaunch-\(UUID().uuidString)")
    // A nonexistent, isolated root represents a fresh install without touching real profiles.
    let services = GatewaySelection.makeServices(environment: ["INBOXPLUS_RUNTIME_ROOT": root.path])
    let snapshot = try await services.gateway.loadSnapshot()
    #expect(snapshot.accounts.isEmpty)
    #expect(snapshot.conversations.isEmpty)
    #expect(snapshot.messagesByRoute.isEmpty)
    #expect(services.directory.people.isEmpty)
    #expect(services.directory.links.isEmpty)
}
