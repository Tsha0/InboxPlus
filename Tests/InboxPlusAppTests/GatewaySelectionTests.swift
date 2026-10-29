import Foundation
import Testing
import InboxPlusCore
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

@Test func bundledFreshInstallSelectsDefaultProfileWithoutManualSetup() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("InboxPlusSelection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let package = root.appendingPathComponent("package")
    let python = package.appendingPathComponent("Runtime/Python/bin/python3.12")
    try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("placeholder".utf8).write(to: python)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
    let environment = ["INBOXPLUS_RUNTIME_ROOT": root.appendingPathComponent("profiles").path,
                       "INBOXPLUS_RUNTIME_PACKAGE_ROOT": package.path]
    #expect(GatewaySelection.resolveProfileName(environment: environment) == "default")
    var named = environment
    named["INBOXPLUS_PROFILE"] = "work"
    #expect(GatewaySelection.resolveProfileName(environment: named) == "work")
}

@MainActor
@Test func demoLaunchNeverAttachesToAProfileEvenWhenOneIsNamed() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxPlusDemoLaunch-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = ["INBOXPLUS_DEMO": "1", "INBOXPLUS_PROFILE": "real", "INBOXPLUS_RUNTIME_ROOT": root.path]

    let services = GatewaySelection.makeServices(environment: environment)
    let snapshot = try await services.gateway.loadSnapshot()

    #expect(!snapshot.conversations.isEmpty)
    #expect(services.favouriteStore == nil)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    // No bridge can be installed into a demo, and a login must never reach a real profile.
    #expect(BridgeSelection.makeProvider(environment: environment) == nil)
}

@Test func demoRequiresTheExactOptIn() {
    #expect(DemoInbox.isRequested(environment: ["INBOXPLUS_DEMO": "1"]))
    #expect(!DemoInbox.isRequested(environment: [:]))
    #expect(!DemoInbox.isRequested(environment: ["INBOXPLUS_DEMO": "0"]))
    #expect(!DemoInbox.isRequested(environment: ["INBOXPLUS_DEMO": "yes"]))
}

/// The inbox drops a conversation whose account or identity it does not know, so inconsistent
/// demo data would not fail loudly: it would just be missing from the window.
@Test func demoDataIsInternallyConsistent() throws {
    let snapshot = DemoInbox.makeSnapshot(now: Date(timeIntervalSince1970: 1_000_000))
    try AccountPolicy.validate(snapshot.accounts)

    let accountIDs = Set(snapshot.accounts.map(\.id))
    let identities = Dictionary(uniqueKeysWithValues: snapshot.identities.map { ($0.id, $0) })
    #expect(Set(snapshot.conversations.map(\.id)).count == snapshot.conversations.count)
    #expect(snapshot.conversations.count == snapshot.messagesByRoute.count)

    for conversation in snapshot.conversations {
        #expect(accountIDs.contains(conversation.accountID))
        #expect(identities[conversation.identityID]?.accountID == conversation.accountID)
        let thread = try #require(snapshot.messagesByRoute[conversation.route])
        #expect(!thread.isEmpty)
        #expect(thread.allSatisfy { $0.route == conversation.route })
        for sender in thread.compactMap(\.senderIdentityID) {
            #expect(identities[sender]?.accountID == conversation.accountID)
        }
        #expect(conversation.latestActivity == thread.map(\.timestamp).max())
    }

    let directory = DemoInbox.makeDirectory()
    #expect(directory.people.count == 1)
    let link = try #require(directory.links["demo-maya"])
    #expect(Set(link.remoteIdentityIDs) == ["demo-maya-whatsapp", "demo-maya-instagram"])
    #expect(link.remoteIdentityIDs.allSatisfy { identities[$0] != nil })
}
