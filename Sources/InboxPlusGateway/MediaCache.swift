import CryptoKit
import Foundation
import InboxPlusCore
import UniformTypeIdentifiers

/// What the cache remembers about one stored file.
///
/// The design requires cached media to retain its source adapter, remote message identifier,
/// content type, size, and deep link, so that a file on disk can always be explained and, when it
/// is evicted, fetched again from the place it came from.
public struct MediaCacheRecord: Codable, Hashable, Sendable {
    public let key: String
    public let source: String
    public let accountID: String
    public let messageID: String
    public var mimeType: String?
    public var byteCount: Int
    public var deepLink: VerifiedDeepLink?
    public var lastAccess: Date
    /// False when these bytes cannot be fetched again. Cleanup must never remove one of these.
    public var isReproducible: Bool

    public init(
        key: String,
        source: String,
        accountID: String,
        messageID: String,
        mimeType: String? = nil,
        byteCount: Int,
        deepLink: VerifiedDeepLink? = nil,
        lastAccess: Date,
        isReproducible: Bool = true
    ) {
        self.key = key
        self.source = source
        self.accountID = accountID
        self.messageID = messageID
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.deepLink = deepLink
        self.lastAccess = lastAccess
        self.isReproducible = isReproducible
    }
}

/// Where a cached file came from, recorded at the moment it is stored.
public struct MediaCacheContext: Hashable, Sendable {
    public let accountID: String
    public let messageID: String
    public var deepLink: VerifiedDeepLink?
    /// Set false for bytes InboxPlus cannot fetch again — anything composed locally and not yet sent.
    public var isReproducible: Bool

    public init(
        accountID: String,
        messageID: String,
        deepLink: VerifiedDeepLink? = nil,
        isReproducible: Bool = true
    ) {
        self.accountID = accountID
        self.messageID = messageID
        self.deepLink = deepLink
        self.isReproducible = isReproducible
    }
}

public enum MediaCacheError: Error, Equatable {
    case directoryNotUsable(String)
}

/// A bounded, on-disk cache for media that downloads lazily.
///
/// Eviction is least-recently-used and, critically, only ever touches reproducible files. A file
/// that cannot be fetched again is retained even when that leaves the cache over budget, because
/// the design forbids deleting irreplaceable local content without explicit consent — being over
/// budget is a smaller harm than losing something permanently.
public actor MediaCache {
    public static let defaultBudgetBytes = 2 * 1024 * 1024 * 1024

    private let directory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    public let budgetBytes: Int

    private var records: [String: MediaCacheRecord] = [:]
    private var downloadGenerations: [String: UInt64] = [:]
    public private(set) var totalBytes: Int = 0
    private var pendingIndexWrite: Task<Void, Never>?

    public init(
        directory: URL,
        budgetBytes: Int = MediaCache.defaultBudgetBytes,
        fileManager: FileManager = .default
    ) throws {
        self.directory = directory
        self.budgetBytes = budgetBytes
        self.fileManager = fileManager
        indexURL = directory.appendingPathComponent("index.json")

        // Media is message content, so the cache is as private as the database beside it.
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MediaCacheError.directoryNotUsable(directory.path)
        }
        records = Self.loadIndex(at: indexURL)
        totalBytes = records.values.reduce(0) { $0 + $1.byteCount }
    }

    deinit { pendingIndexWrite?.cancel() }

    // MARK: - Reading

    /// The file holding this media, or nil when it has not been downloaded yet.
    ///
    /// Reading marks the entry as recently used, which is what keeps a conversation the user is
    /// actually looking at from being evicted out from under them.
    public func cachedFile(for handle: MediaHandle, accountID: String, now: Date = Date()) -> URL? {
        guard let key = recordKey(for: handle.source, accountID: accountID) else { return nil }
        guard var record = records[key] else { return nil }
        let url = fileURL(key: key, mimeType: record.mimeType)
        guard fileManager.fileExists(atPath: url.path) else {
            // The index outlived the file — a deleted cache directory, say. Forget it so the next
            // read downloads instead of reporting a file that is not there.
            records[key] = nil
            totalBytes -= record.byteCount
            try? persistIndex()
            return nil
        }
        record.lastAccess = now
        records[key] = record
        scheduleAccessTimeWrite()
        return url
    }

    public func record(for handle: MediaHandle, accountID: String) -> MediaCacheRecord? {
        guard let key = recordKey(for: handle.source, accountID: accountID) else { return nil }
        return records[key]
    }

    // MARK: - Writing

    func downloadGeneration(accountID: String) -> UInt64 {
        downloadGenerations[accountID, default: 0]
    }

    /// Validate queued downloads on the cache actor too, so a purge cannot run before a stale
    /// store and then have that store recreate the file when actor jobs resume in a different order.
    func storeDownloaded(
        _ data: Data, for handle: MediaHandle, context: MediaCacheContext, generation: UInt64
    ) throws -> URL {
        guard downloadGenerations[context.accountID, default: 0] == generation else {
            throw CancellationError()
        }
        return try store(data, for: handle, context: context)
    }

    @discardableResult
    public func store(
        _ data: Data,
        for handle: MediaHandle,
        context: MediaCacheContext,
        now: Date = Date()
    ) throws -> URL {
        let key = recordKey(for: handle.source, accountID: context.accountID)
            ?? Self.key(for: handle.source, accountID: context.accountID)
        let mimeType = handle.mimeType
        let url = fileURL(key: key, mimeType: mimeType)
        let previousURL = records[key].map { fileURL(key: key, mimeType: $0.mimeType) }
        // Written user-only, like every other secret-adjacent file the runtime produces.
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if let previousURL, previousURL != url, fileManager.fileExists(atPath: previousURL.path) {
            do { try fileManager.removeItem(at: previousURL) }
            catch {
                try? fileManager.removeItem(at: url)
                throw error
            }
        }

        totalBytes += data.count - (records[key]?.byteCount ?? 0)
        records[key] = MediaCacheRecord(
            key: key,
            source: handle.source,
            accountID: context.accountID,
            messageID: context.messageID,
            mimeType: mimeType,
            byteCount: data.count,
            deepLink: context.deepLink,
            lastAccess: now,
            isReproducible: context.isReproducible
        )
        try persistIndex()
        return url
    }

    // MARK: - Cleanup

    /// Evicts least-recently-used reproducible files until the cache fits its budget.
    ///
    /// Returns the keys removed, so a caller can say what happened rather than silently shrinking.
    @discardableResult
    public func evictToFitBudget() throws -> [String] {
        var total = totalBytes
        guard total > budgetBytes else { return [] }

        let candidates = records.values
            .filter(\.isReproducible)
            .sorted { $0.lastAccess < $1.lastAccess }

        var evicted: [String] = []
        for record in candidates where total > budgetBytes {
            let file = fileURL(key: record.key, mimeType: record.mimeType)
            if fileManager.fileExists(atPath: file.path) {
                do { try fileManager.removeItem(at: file) } catch { continue }
            }
            records[record.key] = nil
            totalBytes -= record.byteCount
            total -= record.byteCount
            evicted.append(record.key)
        }
        if !evicted.isEmpty { try persistIndex() }
        return evicted
    }

    /// Removes every cached file for one account, used when an account is erased.
    @discardableResult
    public func purge(accountID: String) throws -> [String] {
        downloadGenerations[accountID, default: 0] &+= 1
        let doomed = records.values.filter { $0.accountID == accountID }
        var removed: [String] = []
        do {
            for record in doomed {
                let file = fileURL(key: record.key, mimeType: record.mimeType)
                if fileManager.fileExists(atPath: file.path) { try fileManager.removeItem(at: file) }
                records[record.key] = nil
                totalBytes -= record.byteCount
                removed.append(record.key)
            }
            if !removed.isEmpty { try persistIndex() }
            return removed
        } catch {
            if !removed.isEmpty { try? persistIndex() }
            throw error
        }
    }

    // MARK: - Storage

    /// Scope bytes to their account, including when two accounts reference the same remote URI.
    /// Length-prefixing the account prevents ambiguous concatenations from sharing a filename.
    static func key(for source: String, accountID: String) -> String {
        "v2-" + legacyKey(for: "\(accountID.utf8.count):\(accountID)\(source)")
    }

    private static func legacyKey(for source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func recordKey(for source: String, accountID: String) -> String? {
        let scoped = Self.key(for: source, accountID: accountID)
        if records[scoped]?.accountID == accountID, records[scoped]?.source == source { return scoped }
        // Existing caches remain usable by their recorded owner, including irreplaceable drafts.
        // New accounts get separate files without copying or deleting the previous owner's bytes.
        let legacy = Self.legacyKey(for: source)
        return records[legacy]?.accountID == accountID && records[legacy]?.source == source ? legacy : nil
    }

    /// The extension matters: AVFoundation and NSImage both do a better job when the file name
    /// admits what it holds.
    static func pathExtension(forMimeType mimeType: String?) -> String? {
        guard let mimeType, let type = UTType(mimeType: mimeType) else { return nil }
        return type.preferredFilenameExtension
    }

    private func fileURL(key: String, mimeType: String?) -> URL {
        guard let ext = Self.pathExtension(forMimeType: mimeType) else {
            return directory.appendingPathComponent(key)
        }
        return directory.appendingPathComponent(key).appendingPathExtension(ext)
    }

    private func persistIndex() throws {
        pendingIndexWrite?.cancel()
        pendingIndexWrite = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: indexURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }

    // Last access is an eviction hint. Batch it separately from durable file/index changes so
    // scrolling through cached attachments does not rewrite the whole index for every hit.
    private func scheduleAccessTimeWrite() {
        guard pendingIndexWrite == nil else { return }
        pendingIndexWrite = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            try? await self?.flushAccessTimes()
        }
    }

    func flushAccessTimes() throws {
        pendingIndexWrite = nil
        try persistIndex()
    }

    /// A corrupt or unreadable index costs the user a re-download, never a crash on launch.
    private static func loadIndex(at url: URL) -> [String: MediaCacheRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: MediaCacheRecord].self, from: data)) ?? [:]
    }
}
