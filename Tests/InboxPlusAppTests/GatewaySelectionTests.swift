import Foundation
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp
@testable import InboxPlusMatrix

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

@Test func theMediaFetcherSharesTheClientTheMatrixGatewayConnects() throws {
    // Break caught: media was given a second Matrix client that nothing ever connected, so every
    // image, video and shared post failed with "InboxPlusMatrixClientError error 1".
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches/InboxPlusMediaWiring-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "alpha")
    let state = RuntimeProfileState(
        serverName: "inboxplus.localhost",
        registrationSecret: "registration-secret",
        launchExecutable: "/usr/bin/true",
        virtualEnvironmentPython: "/usr/bin/true",
        configurationFile: paths.configuration.appendingPathComponent("homeserver.yaml").path,
        snapshot: try RuntimeSnapshot(
            phase: .healthy,
            processIdentity: ManagedProcessIdentity(
                executablePath: "/usr/bin/true",
                launchTimestamp: Date(timeIntervalSince1970: 1),
                processIdentifier: 4_242,
                startIdentityToken: "4242:1:0"
            ),
            loopbackPort: 18_008,
            restartCount: 0,
            lastHealthResult: "healthy",
            diagnosticLogDirectory: nil,
            lastError: nil
        )
    )

    let built = try GatewaySelection.makeMatrixGateway(paths: paths, state: state, makeIMessage: { _ in nil })

    let matrix = try #require(built.gateway as? MatrixMessagingGateway)
    #expect(built.media.client === matrix.mediaFetcher.client)
}

private struct ServingFetcher: RemoteMediaFetching {
    func fetch(_ handle: MediaHandle) async throws -> Data { Data("image bytes".utf8) }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func attachedMediaDownloadsThroughTheFetcherTheGatewayHandsOver() async throws {
    // Break caught: media was given a second Matrix client that nothing ever connected, so every
    // image, video and shared post failed with "InboxPlusMatrixClientError error 1".
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches/InboxPlusMediaWiring-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "alpha")
    let media = MediaController()

    await GatewaySelection.attachMedia(media, fetcher: ServingFetcher(), paths: paths)

    let photo = MessageAttachment(
        id: "a1",
        kind: .image,
        source: MediaHandle(source: "mxc://inboxplus.localhost/1", mimeType: "image/png")
    )
    media.load(photo, accountID: "instagram", messageID: "$1")
    let deadline = ContinuousClock().now.advanced(by: .seconds(50))
    while ContinuousClock().now < deadline, media.state(for: photo) == .loading {
        try await Task.sleep(for: .milliseconds(10))
    }
    guard case let .ready(url) = media.state(for: photo) else {
        Issue.record("expected the photo to download, got \(media.state(for: photo))")
        return
    }
    #expect(url.path.hasPrefix(paths.profile.appendingPathComponent("media").path + "/"))
    #expect(try Data(contentsOf: url) == Data("image bytes".utf8))
}
