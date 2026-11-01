import Foundation
import Testing
@testable import InboxPlusMatrix
import InboxPlusRuntime

@Test func theGatewaysMediaFetcherUsesTheClientTheGatewayConnects() throws {
    // Break caught: media was fetched through a second client that nothing ever connected, so
    // every download failed with `.notConnected` while the gateway's own client was online.
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches", isDirectory: true)
        .appendingPathComponent("InboxPlusMatrixMediaTests-\(UUID().uuidString)", isDirectory: true)
    let paths = try RuntimePaths(root: root, profileName: "alpha")
    let homeserver = URL(string: "http://127.0.0.1:8008")!
    let client = InboxPlusMatrixClient(
        homeserverURL: homeserver,
        store: MatrixClientStore(
            profile: paths,
            keychain: MatrixKeychain(service: "org.inboxplus.tests.\(UUID().uuidString)")
        ),
        provisioner: try MatrixAccountProvisioner(
            baseURL: homeserver,
            serverName: "inboxplus.localhost",
            registrationSecret: "registration-secret"
        )
    )
    let gateway = MatrixMessagingGateway(client: client)

    #expect(gateway.mediaFetcher.client === client)
}

@Test func aClientErrorReadsAsPlainWordsOnScreen() {
    // Break caught: a send made before the client connected showed "The operation couldn't be
    // completed. (InboxPlusMatrix.InboxPlusMatrixClientError error 1.)".
    #expect(
        InboxPlusMatrixClientError.notConnected.localizedDescription
            == "Inbox+ isn't connected yet. Try again in a moment."
    )
    #expect(
        !InboxPlusMatrixClientError.sessionRestoreFailed("M_UNKNOWN_TOKEN").localizedDescription
            .contains("InboxPlusMatrixClientError")
    )
    #expect(
        MatrixGatewayError.unknownRoom("!portal:inboxplus.localhost").localizedDescription
            == "This conversation isn't available anymore."
    )
}
