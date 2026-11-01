import Testing
import InboxPlusCore
@testable import InboxPlusUI

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
