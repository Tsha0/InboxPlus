import MatrixRustSDK
import Testing
@testable import InboxPlusMatrix

@Test func readingAConversationNeverSendsAReceiptTheBridgesPassOnAsSeen() {
    #expect(MatrixMessagingGateway.readReceiptType == .readPrivate)
}
