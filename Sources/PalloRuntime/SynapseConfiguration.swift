import Darwin
import Foundation

public struct SynapseCredentials: Sendable, Equatable {
    public let registrationSecret: String

    public init(registrationSecret: String) {
        self.registrationSecret = registrationSecret
    }
}

public struct SynapseConfiguration: Sendable {
    public static let filePermissions = 0o600

    public let serverName: String
    public let bindAddress: String
    public let port: UInt16
    public let databasePath: URL
    public let mediaPath: URL
    public let signingKeyPath: URL
    public let credentials: SynapseCredentials

    private let pidFilePath: URL

    public init(profile: RuntimePaths, port: UInt16, credentials: SynapseCredentials) {
        self.init(
            profile: profile,
            bindAddress: "127.0.0.1",
            port: port,
            credentials: credentials
        )
    }

    init(
        profile: RuntimePaths,
        bindAddress: String,
        port: UInt16,
        credentials: SynapseCredentials
    ) {
        serverName = "pallo.localhost"
        self.bindAddress = bindAddress
        self.port = port
        databasePath = profile.data.appendingPathComponent("homeserver.db", isDirectory: false)
        mediaPath = profile.data.appendingPathComponent("media", isDirectory: true)
        signingKeyPath = profile.configuration.appendingPathComponent("pallo.signing.key", isDirectory: false)
        self.credentials = credentials
        pidFilePath = profile.state.appendingPathComponent("homeserver.pid", isDirectory: false)
    }

    public func validate() throws {
        guard bindAddress == "127.0.0.1" else {
            throw SynapseConfigurationError.nonLoopbackAddress(bindAddress)
        }
        guard port != 0 else {
            throw SynapseConfigurationError.invalidPort(port)
        }
        guard !credentials.registrationSecret.isEmpty else {
            throw SynapseConfigurationError.emptyRegistrationSecret
        }
        guard !credentials.registrationSecret.contains(where: { $0.isNewline || $0 == "\0" }) else {
            throw SynapseConfigurationError.invalidRegistrationSecret
        }
    }

    public func render() throws -> String {
        try validate()

        return """
        server_name: \(yamlString(serverName))
        pid_file: \(yamlString(pidFilePath.path))
        listeners:
          - port: \(port)
            bind_addresses: ['127.0.0.1']
            type: http
            tls: false
            x_forwarded: false
            resources:
              - names: [client]
                compress: false
        database:
          name: sqlite3
          args:
            database: \(yamlString(databasePath.path))
        media_store_path: \(yamlString(mediaPath.path))
        signing_key_path: \(yamlString(signingKeyPath.path))
        trusted_key_servers: []
        suppress_key_server_warning: true
        enable_registration: false
        registration_shared_secret: \(yamlString(credentials.registrationSecret))
        allow_guest_access: false
        enable_3pid_lookup: false
        enable_room_list_search: false
        room_list_publication_rules: []
        allow_public_rooms_without_auth: false
        allow_public_rooms_over_federation: false
        url_preview_enabled: false
        enable_metrics: false
        report_stats: false
        federation_domain_whitelist: []
        federation_whitelist_endpoint_enabled: false
        send_federation: false
        """
    }

    public func write(to url: URL) throws {
        let yaml = try render()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(Self.filePermissions))
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard fchmod(descriptor, mode_t(Self.filePermissions)) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(descriptor)
            throw error
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(yaml.utf8))
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func yamlString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

public enum SynapseConfigurationError: Error, Equatable, Sendable {
    case nonLoopbackAddress(String)
    case invalidPort(UInt16)
    case emptyRegistrationSecret
    case invalidRegistrationSecret
}
