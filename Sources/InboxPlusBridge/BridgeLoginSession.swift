import Foundation

/// The seam between the login UI and a running bridge.
///
/// The same seam the messaging gateway uses: `InboxPlusFeatures` and `InboxPlusUI` drive a login through
/// this protocol, so neither has to know that a real bridge is an external process reached over a
/// loopback HTTP API — and tests drive the whole flow with no process at all.
public protocol BridgeLoginSession: Sendable {
    func loginFlows() async throws -> [BridgeLoginFlow]
    func startLogin(flowID: String) async throws -> BridgeLoginStep
    func submit(
        loginID: String,
        stepID: String,
        type: BridgeLoginStepType,
        values: [String: String]
    ) async throws -> BridgeLoginStep
    /// Tells the bridge an attempt is over, so it drops the connection it opened to the network.
    ///
    /// An abandoned attempt is not free: a login holds an open network session for as long as
    /// the bridge keeps it, and a bridge refuses to start more once too many are in flight. Walking
    /// away from a login has to end it on the bridge too, not only in the window.
    func cancelLogin(loginID: String) async throws
}
