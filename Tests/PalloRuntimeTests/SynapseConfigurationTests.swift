import Foundation
import Testing
@testable import PalloRuntime

@Test func renderedConfigurationIsPrivateAndLoopbackOnly() throws {
    // Break caught: a listener is exposed beyond IPv4 loopback or enables a non-client resource.
    let yaml = try fixtureConfiguration(port: 18_008).render()

    #expect(yaml.contains("bind_addresses: ['127.0.0.1']"))
    #expect(yaml.contains("port: 18008"))
    #expect(yaml.contains("names: [client]"))
    #expect(!yaml.contains("names: [client, federation]"))
    #expect(!yaml.contains("names: [federation]"))
    #expect(yaml.contains("send_federation: false"))
}

@Test func renderedConfigurationDisablesPublicFeaturesAndKeepsLocalAdminSecret() throws {
    // Break caught: an accidental change enables an unauthenticated/public Synapse feature or omits local admin setup.
    let yaml = try fixtureConfiguration().render()

    #expect(yaml.contains("enable_registration: false"))
    #expect(yaml.contains("allow_guest_access: false"))
    #expect(yaml.contains("enable_room_list_search: false"))
    #expect(yaml.contains("room_list_publication_rules: []"))
    #expect(yaml.contains("allow_public_rooms_without_auth: false"))
    #expect(yaml.contains("allow_public_rooms_over_federation: false"))
    #expect(yaml.contains("url_preview_enabled: false"))
    #expect(yaml.contains("report_stats: false"))
    #expect(yaml.contains("registration_shared_secret: 'registration-secret'"))
}

@Test func nonLoopbackListenerIsRejected() throws {
    // Break caught: configuration validation accepts a remotely reachable listener.
    let configuration = try fixtureConfiguration(bindAddress: "0.0.0.0")

    #expect(throws: SynapseConfigurationError.nonLoopbackAddress("0.0.0.0")) {
        try configuration.validate()
    }
}

@Test func configurationRequiresAnAdministrationSecret() throws {
    // Break caught: configuration renders without the secret required for authenticated local administration.
    let configuration = try fixtureConfiguration(registrationSecret: "")

    #expect(throws: SynapseConfigurationError.emptyRegistrationSecret) {
        try configuration.validate()
    }
}

@Test func writesSecretBearingConfigurationWithUserOnlyPermissions() throws {
    // Break caught: the generated file containing the administration secret is readable by other local users.
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".build/SynapseConfigurationTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configurationFile = directory.appendingPathComponent("homeserver.yaml", isDirectory: false)
    let configuration = try fixtureConfiguration()

    try configuration.write(to: configurationFile)

    let attributes = try FileManager.default.attributesOfItem(atPath: configurationFile.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o600)
    #expect(try String(contentsOf: configurationFile, encoding: .utf8) == configuration.render())
}

private func fixtureConfiguration(
    bindAddress: String = "127.0.0.1",
    port: UInt16 = 18_008,
    registrationSecret: String = "registration-secret"
) throws -> SynapseConfiguration {
    SynapseConfiguration(
        profile: try fixtureProfile(),
        bindAddress: bindAddress,
        port: port,
        credentials: SynapseCredentials(registrationSecret: registrationSecret)
    )
}

private func fixtureProfile() throws -> RuntimePaths {
    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return try RuntimePaths(
        root: workingDirectory.appendingPathComponent(".build/pallo-runtime-tests", isDirectory: true),
        profileName: "configuration-tests"
    )
}
