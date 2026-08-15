import Foundation
import PalloBridge
import PalloRuntime

/// Speaks the mautrix `bridgev2` provisioning API over loopback.
///
/// Reuses `MatrixHTTPClient`, so bridge provisioning inherits the same loopback-only enforcement,
/// percent-encoded paths, and redacted authorization headers as Matrix traffic.
///
/// Every request carries `?user_id=`: a bridge serves many Matrix users, and without it the
/// request is attributed to nobody and refused as lacking login permission.
public struct BridgeProvisioningClient: BridgeLoginSession, Sendable {
    private let client: MatrixHTTPClient
    private let userID: String

    public init(
        baseURL: URL,
        provisioningToken: String,
        userID: String,
        transport: any SynapseHTTPTransport = URLSessionSynapseHTTPTransport()
    ) throws {
        client = try MatrixHTTPClient(
            baseURL: baseURL,
            accessToken: provisioningToken,
            transport: transport
        )
        self.userID = userID
    }

    private var actingUser: [URLQueryItem] { [URLQueryItem(name: "user_id", value: userID)] }

    public func loginFlows() async throws -> [BridgeLoginFlow] {
        let response: FlowsResponse = try await client.send(
            .get,
            path: ["_matrix", "provision", "v3", "login", "flows"],
            query: actingUser,
            idempotent: true
        )
        return response.flows
    }

    public func startLogin(flowID: String) async throws -> BridgeLoginStep {
        try await client.send(
            .post,
            path: ["_matrix", "provision", "v3", "login", "start", flowID],
            query: actingUser,
            body: Data("{}".utf8)
        )
    }

    /// Submits a step's collected values and returns whatever the bridge asks for next.
    public func submit(
        loginID: String,
        stepID: String,
        type: BridgeLoginStepType,
        values: [String: String]
    ) async throws -> BridgeLoginStep {
        try await client.send(
            .post,
            path: ["_matrix", "provision", "v3", "login", "step", loginID, stepID, type.rawValue],
            query: actingUser,
            body: try JSONSerialization.data(withJSONObject: values)
        )
    }

    /// Validates values against the step's own declared fields before anything leaves the machine.
    ///
    /// The rules live on `BridgeLoginStep` so the UI can apply them on every keystroke without a
    /// client; this stays as the name the provisioning call sites already use.
    public static func validate(
        _ values: [String: String],
        against step: BridgeLoginStep
    ) throws {
        try step.validate(values)
    }
}

private struct FlowsResponse: Decodable {
    let flows: [BridgeLoginFlow]
}
