import Foundation
import PalloRuntime

/// Speaks the mautrix `bridgev2` provisioning API over loopback.
///
/// Reuses `MatrixHTTPClient`, so bridge provisioning inherits the same loopback-only enforcement,
/// percent-encoded paths, and redacted authorization headers as Matrix traffic.
public struct BridgeProvisioningClient: Sendable {
    private let client: MatrixHTTPClient

    public init(
        baseURL: URL,
        provisioningToken: String,
        transport: any SynapseHTTPTransport = URLSessionSynapseHTTPTransport()
    ) throws {
        client = try MatrixHTTPClient(
            baseURL: baseURL,
            accessToken: provisioningToken,
            transport: transport
        )
    }

    public func loginFlows() async throws -> [BridgeLoginFlow] {
        let response: FlowsResponse = try await client.send(
            .get,
            path: ["_matrix", "provision", "v3", "login", "flows"],
            idempotent: true
        )
        return response.flows
    }

    public func startLogin(flowID: String) async throws -> BridgeLoginStep {
        try await client.send(
            .post,
            path: ["_matrix", "provision", "v3", "login", "start", flowID],
            body: Data("{}".utf8)
        )
    }

    /// Submits a step's collected values and returns whatever the bridge asks for next.
    public func submit(
        stepID: String,
        type: BridgeLoginStepType,
        values: [String: String]
    ) async throws -> BridgeLoginStep {
        try await client.send(
            .post,
            path: ["_matrix", "provision", "v3", "login", "step", stepID, type.rawValue],
            body: try JSONSerialization.data(withJSONObject: values)
        )
    }

    /// Validates values against the step's own declared fields before anything leaves the machine.
    public static func validate(
        _ values: [String: String],
        against step: BridgeLoginStep
    ) throws {
        switch step.type {
        case .userInput:
            for field in step.userInput?.fields ?? [] {
                guard let value = values[field.id], !value.isEmpty else {
                    throw BridgeLoginError.missingRequiredField(field.id)
                }
                guard field.accepts(value) else {
                    throw BridgeLoginError.invalidFieldValue(field.id)
                }
            }
        case .cookies:
            for id in step.cookies?.requiredFieldIDs ?? [] {
                guard let value = values[id], !value.isEmpty else {
                    throw BridgeLoginError.missingRequiredField(id)
                }
            }
        default:
            break
        }
    }
}

private struct FlowsResponse: Decodable {
    let flows: [BridgeLoginFlow]
}
