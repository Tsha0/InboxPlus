import Testing
import InboxPlusCore
@testable import InboxPlusUI

@MainActor
@Test func anAccountRowNamesWhoIsSignedInRatherThanRepeatingTheNetwork() {
    let instagram = ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram")
    #expect(AccountsListView.identityLine(instagram, signedInAs: "@jason.s") == "@jason.s")
    // Unknown, or only the network's own name again: the line is left out.
    #expect(AccountsListView.identityLine(instagram, signedInAs: nil) == nil)
    #expect(AccountsListView.identityLine(instagram, signedInAs: "  ") == nil)
    #expect(AccountsListView.identityLine(instagram, signedInAs: "instagram") == nil)
    let messenger = ConnectedAccount(id: "facebookmessenger", platform: .facebookMessenger, displayName: "Messenger")
    #expect(AccountsListView.identityLine(messenger, signedInAs: "Messenger") == nil)
}

@Test func aBridgeReportingTroubleSaysSoInSettings() {
    func problem(_ state: NetworkConnectionState?) -> String? {
        AccountsListView.networkProblem(
            ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram", networkState: state)
        )
    }
    #expect(problem(nil) == nil)
    #expect(problem(.connected) == nil)
    #expect(problem(.reconnecting) == "Instagram dropped the connection — reconnecting…")
    #expect(problem(.badCredentials) == "Signed out of Instagram — remove it and add it again")
    #expect(problem(.signedOut) == "Signed out of Instagram — remove it and add it again")
}
