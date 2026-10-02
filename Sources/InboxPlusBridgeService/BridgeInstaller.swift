import CryptoKit
import Darwin
import Foundation
import InboxPlusBridge
import InboxPlusRuntime

public enum BridgeInstallError: Error, Equatable, Sendable, CustomStringConvertible {
    case nothingToInstall(String)
    case downloadFailed(bridge: String, status: Int)
    case transport(bridge: String, reason: String)
    case checksumMismatch(bridge: String, expected: String, actual: String)
    case emptyDownload(String)
    case cannotWrite(URL)
    case notExecutable(URL)

    public var description: String {
        switch self {
        case let .nothingToInstall(id):
            "bridge '\(id)' has no downloadable artifact"
        case let .downloadFailed(bridge, status):
            "downloading bridge '\(bridge)' failed with HTTP \(status)"
        case let .transport(bridge, reason):
            "downloading bridge '\(bridge)' failed: \(reason)"
        case let .checksumMismatch(bridge, expected, actual):
            "bridge '\(bridge)' failed verification: expected SHA-256 \(expected), got \(actual)"
        case let .emptyDownload(bridge):
            "bridge '\(bridge)' downloaded zero bytes"
        case let .cannotWrite(url):
            "cannot write \(url.path)"
        case let .notExecutable(url):
            "\(url.path) is not executable"
        }
    }
}

/// Downloads artifacts into non-executable staging files. The data method remains a small
/// fixture seam; production fetchers stream directly to disk.
public protocol BridgeArtifactFetching: Sendable {
    func fetch(_ url: URL) async throws -> (status: Int, body: Data)
    func fetch(_ url: URL, to destination: URL) async throws -> Int
}

public extension BridgeArtifactFetching {
    func fetch(_ url: URL, to destination: URL) async throws -> Int {
        let (status, body) = try await fetch(url)
        try body.write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return status
    }
}

public struct URLSessionBridgeArtifactFetcher: BridgeArtifactFetching {
    private let maximumBytes: Int
    private let session: URLSession

    public init(maximumBytes: Int = 256 * 1_024 * 1_024, session: URLSession = .shared) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
        self.session = session
    }

    public func fetch(_ url: URL) async throws -> (status: Int, body: Data) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("inboxplus-artifact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let status = try await fetch(url, to: file)
        return (status, try Data(contentsOf: file))
    }

    public func fetch(_ url: URL, to destination: URL) async throws -> Int {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.httpMethod = "GET"
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        let exceededLimit = BridgeInstallError.transport(
            bridge: url.lastPathComponent,
            reason: "response exceeded \(maximumBytes) bytes"
        )
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            throw exceededLimit
        }
        try Data().write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let output = try FileHandle(forWritingTo: destination)
        var completed = false
        defer {
            try? output.close()
            if !completed { try? FileManager.default.removeItem(at: destination) }
        }
        var chunk = Data()
        chunk.reserveCapacity(64 * 1_024)
        var count = 0
        for try await byte in bytes {
            guard count < maximumBytes else { throw exceededLimit }
            count += 1
            chunk.append(byte)
            if chunk.count == 64 * 1_024 {
                try output.write(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        try output.write(contentsOf: chunk)
        try output.synchronize()
        completed = true
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

public struct InstalledBridge: Sendable, Equatable {
    public let descriptor: BridgeDescriptor
    public let executable: URL
    public let sha256: String

    public init(descriptor: BridgeDescriptor, executable: URL, sha256: String) {
        self.descriptor = descriptor
        self.executable = executable
        self.sha256 = sha256
    }
}

/// Downloads a pinned bridge binary, verifies it, and installs it under the profile.
///
/// The ordering here is the whole point: bytes are hashed and compared *before* anything is marked
/// executable, and a mismatch never touches the install path. A bridge binary is code Inbox+ runs
/// with the user's messages in reach, so a release page alone is not sufficient provenance.
public struct BridgeInstaller: Sendable {
    public static let executablePermissions = 0o700
    public static let directoryPermissions = 0o700

    private let paths: RuntimePaths
    private let fetcher: any BridgeArtifactFetching

    public init(paths: RuntimePaths, fetcher: any BridgeArtifactFetching = URLSessionBridgeArtifactFetcher()) {
        self.paths = paths
        self.fetcher = fetcher
    }

    /// `<profile>/bridges/<id>` — binary, configuration, database, and logs for one bridge.
    public func directory(for descriptor: BridgeDescriptor) -> URL {
        paths.profile
            .appendingPathComponent("bridges", isDirectory: true)
            .appendingPathComponent(descriptor.id, isDirectory: true)
    }

    /// Installed binaries carry their version in the name, so a version bump cannot be mistaken
    /// for the binary already on disk.
    public func executable(for descriptor: BridgeDescriptor) -> URL {
        directory(for: descriptor)
            .appendingPathComponent("\(descriptor.id)-\(descriptor.version)", isDirectory: false)
    }

    public func isInstalled(_ descriptor: BridgeDescriptor) -> Bool {
        FileManager.default.isExecutableFile(atPath: executable(for: descriptor).path)
    }

    /// Installs `descriptor` if it is not already present and verified.
    ///
    /// An already-installed binary is re-hashed rather than trusted by path: the check is cheap
    /// next to the download, and it catches a binary that was swapped after installation.
    @discardableResult
    public func install(_ descriptor: BridgeDescriptor) async throws -> InstalledBridge {
        guard let artifact = descriptor.artifact else {
            throw BridgeInstallError.nothingToInstall(descriptor.id)
        }
        let destination = executable(for: descriptor)

        if FileManager.default.fileExists(atPath: destination.path),
           let existingHash = try? Self.hash(fileAt: destination),
           existingHash == artifact.sha256 {
            try Self.setPermissions(Self.executablePermissions, on: destination)
            return InstalledBridge(
                descriptor: descriptor,
                executable: destination,
                sha256: artifact.sha256
            )
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try Self.setPermissions(Self.directoryPermissions, on: directory)
        let staging = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staging) }
        let status: Int
        do {
            status = try await fetcher.fetch(artifact.downloadURL, to: staging)
        } catch let error as BridgeInstallError {
            throw error
        } catch {
            throw BridgeInstallError.transport(bridge: descriptor.id, reason: error.localizedDescription)
        }
        guard (200..<300).contains(status) else {
            throw BridgeInstallError.downloadFailed(bridge: descriptor.id, status: status)
        }
        let size = try FileManager.default.attributesOfItem(atPath: staging.path)[.size] as? NSNumber
        guard (size?.uint64Value ?? 0) > 0 else {
            throw BridgeInstallError.emptyDownload(descriptor.id)
        }
        let actual = try Self.hash(fileAt: staging)
        guard actual == artifact.sha256 else {
            throw BridgeInstallError.checksumMismatch(
                bridge: descriptor.id, expected: artifact.sha256, actual: actual
            )
        }
        try Self.syncFile(at: staging)
        try Self.setPermissions(Self.executablePermissions, on: staging)
        guard Darwin.rename(staging.path, destination.path) == 0 else {
            throw BridgeInstallError.cannotWrite(destination)
        }
        guard FileManager.default.isExecutableFile(atPath: destination.path) else {
            throw BridgeInstallError.notExecutable(destination)
        }
        return InstalledBridge(descriptor: descriptor, executable: destination, sha256: actual)
    }

    /// Verifies an installed binary still hashes to its pinned value.
    public func verify(_ descriptor: BridgeDescriptor) throws {
        guard let artifact = descriptor.artifact else {
            throw BridgeInstallError.nothingToInstall(descriptor.id)
        }
        let destination = executable(for: descriptor)
        guard let actual = try? Self.hash(fileAt: destination) else {
            throw BridgeInstallError.cannotWrite(destination)
        }
        guard actual == artifact.sha256 else {
            throw BridgeInstallError.checksumMismatch(
                bridge: descriptor.id,
                expected: artifact.sha256,
                actual: actual
            )
        }
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(fileAt file: URL) throws -> String {
        let descriptor = Darwin.open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw BridgeInstallError.cannotWrite(file) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func setPermissions(_ permissions: Int, on url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    private static func syncFile(at url: URL) throws {
        let descriptor = open(url.path, O_WRONLY)
        guard descriptor >= 0 else { throw BridgeInstallError.cannotWrite(url) }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else { throw BridgeInstallError.cannotWrite(url) }
    }
}
