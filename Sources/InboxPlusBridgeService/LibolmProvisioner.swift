import Darwin
import Foundation
import InboxPlusRuntime

public enum LibolmError: Error, Equatable, Sendable, CustomStringConvertible {
    case cmakeMissing
    case downloadFailed(status: Int)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case patchDidNotApply
    case configureFailed(String)
    case buildFailed(String)
    case libraryMissingAfterBuild(URL)
    case cannotWrite(URL)

    public var description: String {
        switch self {
        case .cmakeMissing:
            "cmake is required to build libolm; install it with: brew install cmake"
        case let .downloadFailed(status):
            "downloading the libolm source failed with HTTP \(status)"
        case let .checksumMismatch(expected, actual):
            "the libolm source failed verification: expected SHA-256 \(expected), got \(actual)"
        case let .extractionFailed(reason):
            "could not extract the libolm source: \(reason)"
        case .patchDidNotApply:
            "the pinned libolm patch no longer matches its source; the pin must be reviewed"
        case let .configureFailed(reason):
            "configuring the libolm build failed: \(reason)"
        case let .buildFailed(reason):
            "building libolm failed: \(reason)"
        case let .libraryMissingAfterBuild(url):
            "libolm built but \(url.lastPathComponent) is not where it was expected"
        case let .cannotWrite(url):
            "cannot write \(url.path)"
        }
    }
}

/// Installs the bundled `libolm.3.dylib` beside a bridge binary, or builds pinned source once.
///
/// The app ships the library built from a checksum-verified tarball and signs it with the other
/// runtime resources. Development builds reuse a private cache keyed by source, patch and flags.
///
/// dyld resolves `@rpath` against the loader's own directory first, so installing the dylib next to
/// the bridge binary needs no `DYLD_*` variables, which macOS strips from hardened processes anyway.
public struct LibolmProvisioner: Sendable {
    public static let version = "3.2.16"
    public static let libraryName = "libolm.3.dylib"
    /// SHA-256 of `olm-3.2.16.tar.gz` from the canonical Matrix.org GitLab archive.
    public static let sourceSHA256 =
        "1e90f9891009965fd064be747616da46b232086fe270b77605ec9bda34272a68"
    public static let sourceURL = URL(
        string: "https://gitlab.matrix.org/matrix-org/olm/-/archive/3.2.16/olm-3.2.16.tar.gz"
    )!

    /// libolm 3.2.16 does not compile with a current clang: `List::operator=` declares its cursor
    /// `T * const` and then increments it. The function has therefore never compiled anywhere, so
    /// it has never run, and it is also wrong in a second way — it dereferences the list rather
    /// than the cursor. libolm is archived, so upstream will not fix it.
    ///
    /// The patch is pinned as an exact before/after pair: if the source ever stops matching
    /// verbatim, the build fails loudly instead of applying a fuzzy edit to a crypto library.
    static let patchTarget = """
            T * this_pos = _data;
            T * const other_pos = other._data;
            while (other_pos != other._end) {
                *this_pos = *other;
                ++this_pos;
                ++other_pos;
            }
    """

    static let patchReplacement = """
            T * this_pos = _data;
            T const * other_pos = other._data;
            while (other_pos != other._end) {
                *this_pos = *other_pos;
                ++this_pos;
                ++other_pos;
            }
    """

    private let fetcher: any BridgeArtifactFetching
    private let cmake: URL?
    private let bundledLibrary: URL?
    private let cacheRoot: URL?
    private let buildLibrary: BuildLibrary?

    typealias BuildLibrary = @Sendable (URL) async throws -> URL

    public init(
        fetcher: any BridgeArtifactFetching = URLSessionBridgeArtifactFetcher(),
        cmake: URL? = LibolmProvisioner.locateCMake(),
        bundledLibrary: URL? = RuntimeProfileService.resolvedPackageRoot()
            .appendingPathComponent("Runtime/libolm.3.dylib"),
        cacheRoot: URL? = nil
    ) {
        self.fetcher = fetcher
        self.cmake = cmake
        self.bundledLibrary = bundledLibrary
        self.cacheRoot = cacheRoot
        buildLibrary = nil
    }

    init(cacheRoot: URL, buildLibrary: @escaping BuildLibrary) {
        fetcher = URLSessionBridgeArtifactFetcher()
        cmake = nil
        bundledLibrary = nil
        self.cacheRoot = cacheRoot
        self.buildLibrary = buildLibrary
    }

    /// All inputs that can change the built library participate in the cache identity.
    static var cacheKey: String {
        BridgeInstaller.hash(Data((sourceSHA256 + "\n" + patchTarget + "\n" + patchReplacement
            + "\narm64\nRelease\nshared\ntests-off\ncmake-policy-3.5\n").utf8))
    }

    public static func locateCMake() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/cmake",
            "/usr/local/bin/cmake",
            "/usr/bin/cmake",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public func isInstalled(in directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(Self.libraryName).path
        )
    }

    /// Uses the signed app resource when available, otherwise reuses a verified source build.
    @discardableResult
    public func install(into directory: URL) async throws -> URL {
        if let bundledLibrary, FileManager.default.fileExists(atPath: bundledLibrary.path) {
            // Bundle signing changes Mach-O bytes after the source build. Verify the installed
            // copy against the signed resource shipped by this application, rather than a build
            // cache receipt written before signing.
            let checksum = try BridgeInstaller.hash(fileAt: bundledLibrary)
            return try install(VerifiedLibolmLibrary(file: bundledLibrary, sha256: checksum), into: directory)
        }
        // Cache location is independent of the destination depth: the build-time bundler also
        // installs into shallow temporary directories, unlike a profile's bridges/<id> directory.
        let root = try cacheRoot ?? RuntimeProfileService.developerRuntimeRoot()
            .appendingPathComponent(".artifact-cache/libolm", isDirectory: true)
        let cacheDirectory = try RuntimePaths(root: root, profileName: Self.cacheKey).profile
        let cached = try await LibolmBuildCache.shared.library(key: cacheDirectory.path) {
            try await verifiedCachedLibrary(in: cacheDirectory)
        }
        return try install(cached, into: directory)
    }

    private func install(_ library: VerifiedLibolmLibrary, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(Self.libraryName)
        if (try? BridgeInstaller.hash(fileAt: destination)) == library.sha256 {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let staging = directory.appendingPathComponent(".libolm-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: library.file, to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        guard try BridgeInstaller.hash(fileAt: staging) == library.sha256,
              Darwin.rename(staging.path, destination.path) == 0 else {
            throw LibolmError.cannotWrite(destination)
        }
        return destination
    }

    private struct CacheReceipt: Codable {
        let key: String
        let sha256: String
    }

    private func verifiedCachedLibrary(in cacheDirectory: URL) async throws -> VerifiedLibolmLibrary {
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let lockFile = cacheDirectory.appendingPathComponent("build.lock")
        let lock: ProfileLock
        while true {
            do { lock = try ProfileLock.acquire(at: lockFile); break }
            catch ProfileLockError.alreadyLocked { try await Task.sleep(for: .milliseconds(100)) }
        }
        defer { withExtendedLifetime(lock) {} }
        let cached = cacheDirectory.appendingPathComponent(Self.libraryName)
        let receiptFile = cacheDirectory.appendingPathComponent("receipt.json")
        if Self.isPrivateRegularFile(cached), Self.isPrivateRegularFile(receiptFile),
           let receiptData = try? Data(contentsOf: receiptFile),
           let receipt = try? JSONDecoder().decode(CacheReceipt.self, from: receiptData),
           receipt.key == Self.cacheKey,
           (try? BridgeInstaller.hash(fileAt: cached)) == receipt.sha256 {
            return VerifiedLibolmLibrary(file: cached, sha256: receipt.sha256)
        }
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let workspace = cacheDirectory.appendingPathComponent(".build-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: workspace) }
        let built: URL
        if let buildLibrary { built = try await buildLibrary(workspace) }
        else { built = try await build(in: workspace) }
        let resolved = built.resolvingSymlinksInPath()
        let checksum = try BridgeInstaller.hash(fileAt: resolved)
        let staging = workspace.appendingPathComponent("verified-libolm")
        try FileManager.default.copyItem(at: resolved, to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        guard try BridgeInstaller.hash(fileAt: staging) == checksum,
              Darwin.rename(staging.path, cached.path) == 0 else { throw LibolmError.cannotWrite(cached) }
        let receipt = try JSONEncoder().encode(CacheReceipt(key: Self.cacheKey, sha256: checksum))
        try receipt.write(to: receiptFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptFile.path)
        return VerifiedLibolmLibrary(file: cached, sha256: checksum)
    }

    private static func isPrivateRegularFile(_ file: URL) -> Bool {
        var metadata = stat()
        return Darwin.lstat(file.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFREG
            && metadata.st_uid == getuid() && metadata.st_nlink == 1 && metadata.st_mode & 0o777 == 0o600
    }

    private func build(in workspace: URL) async throws -> URL {
        guard let cmake else { throw LibolmError.cmakeMissing }
        let tarball = workspace.appendingPathComponent("olm.tar.gz", isDirectory: false)
        let status = try await fetcher.fetch(Self.sourceURL, to: tarball)
        guard (200..<300).contains(status) else {
            throw LibolmError.downloadFailed(status: status)
        }
        let actual = try BridgeInstaller.hash(fileAt: tarball)
        guard actual == Self.sourceSHA256 else {
            throw LibolmError.checksumMismatch(expected: Self.sourceSHA256, actual: actual)
        }

        try Self.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            ["xzf", tarball.path],
            in: workspace,
            failure: LibolmError.extractionFailed
        )
        let source = workspace.appendingPathComponent("olm-\(Self.version)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw LibolmError.extractionFailed("olm-\(Self.version) is not in the archive")
        }
        try applyPinnedPatch(in: source)

        let build = workspace.appendingPathComponent("build", isDirectory: true)
        try Self.run(
            cmake,
            [
                "-S", source.path,
                "-B", build.path,
                // libolm's archived build declares pre-3.5 policies, removed in CMake 4.
                // Set the supported compatibility floor externally without changing the source pin.
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                "-DCMAKE_BUILD_TYPE=Release",
                "-DBUILD_SHARED_LIBS=ON",
                "-DOLM_TESTS=OFF",
                "-DCMAKE_OSX_ARCHITECTURES=arm64",
            ],
            in: workspace,
            failure: LibolmError.configureFailed
        )
        try Self.run(
            cmake,
            ["--build", build.path, "-j", "\(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))"],
            in: workspace,
            failure: LibolmError.buildFailed
        )

        let built = build.appendingPathComponent(Self.libraryName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: built.path) else {
            throw LibolmError.libraryMissingAfterBuild(built)
        }
        // cmake publishes a symlink to the versioned dylib; resolve before deleting the workspace.
        return built.resolvingSymlinksInPath()
    }

    private func applyPinnedPatch(in source: URL) throws {
        let header = source.appendingPathComponent("include/olm/list.hh", isDirectory: false)
        guard let contents = try? String(contentsOf: header, encoding: .utf8),
              contents.contains(Self.patchTarget)
        else { throw LibolmError.patchDidNotApply }
        let patched = contents.replacingOccurrences(
            of: Self.patchTarget,
            with: Self.patchReplacement
        )
        try patched.write(to: header, atomically: true, encoding: .utf8)
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String],
        in directory: URL,
        failure: (String) -> LibolmError
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: output.suffix(2_048), as: UTF8.self)
            throw failure(text.isEmpty ? "exit status \(process.terminationStatus)" : text)
        }
    }
}

private struct VerifiedLibolmLibrary: Sendable {
    let file: URL
    let sha256: String
}

/// Concurrent bridge preparations share one in-flight build without blocking the executor.
private actor LibolmBuildCache {
    static let shared = LibolmBuildCache()
    private var builds: [String: Task<VerifiedLibolmLibrary, any Error>] = [:]

    func library(key: String, operation: @escaping @Sendable () async throws -> VerifiedLibolmLibrary) async throws -> VerifiedLibolmLibrary {
        if let existing = builds[key] { return try await existing.value }
        let task = Task { try await operation() }
        builds[key] = task
        defer { builds[key] = nil }
        return try await task.value
    }
}
