import Foundation
import Testing
@testable import MimoApp

@MainActor
@Test func launchWithoutPreparedProfileContainsNoDemoData() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MimoEmptyLaunch-\(UUID().uuidString)")
    // A nonexistent, isolated root represents a fresh install without touching real profiles.
    let services = GatewaySelection.makeServices(environment: ["MIMO_RUNTIME_ROOT": root.path])
    let snapshot = try await services.gateway.loadSnapshot()
    #expect(snapshot.accounts.isEmpty)
    #expect(snapshot.conversations.isEmpty)
    #expect(snapshot.messagesByRoute.isEmpty)
    #expect(services.directory.people.isEmpty)
    #expect(services.directory.links.isEmpty)
}
