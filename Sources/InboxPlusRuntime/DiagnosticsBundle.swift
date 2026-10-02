import Foundation

/// What a diagnostics export produced, so the caller can tell the user what they are about to send.
public struct DiagnosticsManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let name: String
        public let byteCount: Int
        /// True when the file was truncated to fit the per-file limit.
        public let truncated: Bool
    }

    public let inboxplusVersion: String
    public let profileName: String
    public let entries: [Entry]
    /// Files deliberately left out, with the reason, so an absence is never mistaken for a bug.
    public let excluded: [String]
}

/// Collects a redacted diagnostics bundle from a profile.
///
/// Everything written here has passed through `DiagnosticsRedactor`. The rule is that a bundle is
/// something a user can hand to a stranger, so the question for each file is not "is this useful"
/// but "would I be comfortable if this were posted publicly".
public struct DiagnosticsBundle {
    private let paths: RuntimePaths
    private let redactor: DiagnosticsRedactor
    private let fileManager: FileManager
    /// Logs can reach hundreds of megabytes; a bundle nobody can upload gets sent as a screenshot.
    public let maximumBytesPerFile: Int

    public init(
        paths: RuntimePaths,
        redactor: DiagnosticsRedactor,
        maximumBytesPerFile: Int = 2 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        precondition(maximumBytesPerFile > 0)
        self.paths = paths
        self.redactor = redactor
        self.maximumBytesPerFile = maximumBytesPerFile
        self.fileManager = fileManager
    }

    /// Files that are never collected, whatever redaction could do to them.
    ///
    /// This is a deny-by-pattern rule rather than a list of exact names, because the first version
    /// of it was a list and it leaked: the homeserver's key is called `inboxplus.signing.key`, not
    /// `signing.key`, so an exact match sailed past it and the raw ed25519 key landed in a bundle.
    /// A substring rule fails safe — it can only ever exclude too much, and excluding a log is a
    /// nuisance where including a key is a compromise.
    static let excludedNameFragments = [
        "signing.key", ".key", "keystore", "keychain",
        "credential", "secret", "token", "password", "passphrase",
        ".db", ".sqlite", "matrix-sdk-store", "media",
    ]

    /// True when a file must never be collected, judged by name alone.
    static func isExcluded(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return excludedNameFragments.contains { lowered.contains($0) }
    }

    public func write(
        to destination: URL,
        inboxplusVersion: String
    ) throws -> DiagnosticsManifest {
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var entries: [DiagnosticsManifest.Entry] = []
        var excluded: [String] = []

        for source in collectableFiles() {
            let name = source.lastPathComponent
            if Self.isExcluded(name) {
                excluded.append("\(name) — may hold key material or is not text; never collected")
                continue
            }
            guard let (text, truncated) = try? Self.readTail(
                from: source, limit: maximumBytesPerFile
            ) else {
                excluded.append("\(name) — not readable as text")
                continue
            }
            let redacted = redactor.redact(linesOf: text)
            let target = destination.appendingPathComponent(uniqueName(for: source, in: entries))
            try Data(redacted.utf8).write(to: target, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            entries.append(
                .init(name: target.lastPathComponent, byteCount: redacted.utf8.count, truncated: truncated)
            )
        }

        let manifest = DiagnosticsManifest(
            inboxplusVersion: inboxplusVersion,
            profileName: paths.profile.lastPathComponent,
            entries: entries.sorted { $0.name < $1.name },
            excluded: excluded.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: destination.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        return manifest
    }

    /// Logs and configuration only. State, databases and key material are not walked at all.
    private func collectableFiles() -> [URL] {
        var files: [URL] = []
        for directory in [paths.logs, paths.configuration] {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            files.append(contentsOf: contents.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            })
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Two directories can hold a `config.yaml`, so names are disambiguated by their parent rather
    /// than one silently overwriting the other.
    private func uniqueName(for source: URL, in entries: [DiagnosticsManifest.Entry]) -> String {
        let name = source.lastPathComponent
        guard entries.contains(where: { $0.name == name }) else { return name }
        return "\(source.deletingLastPathComponent().lastPathComponent)-\(name)"
    }

    /// Reads only the bounded tail, dropping a partial first line before UTF-8 decoding.
    static func readTail(from file: URL, limit: Int) throws -> (String, Bool) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let truncated = size > UInt64(limit)
        if truncated { try handle.seek(toOffset: size - UInt64(limit)) }
        else { try handle.seek(toOffset: 0) }
        var data = try handle.read(upToCount: limit) ?? Data()
        if truncated {
            // A token or UTF-8 character can straddle the boundary. Export complete lines only.
            if let newline = data.firstIndex(of: 10) {
                data = Data(data.suffix(from: data.index(after: newline)))
            } else {
                data.removeAll()
            }
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return (text, truncated)
    }
}
