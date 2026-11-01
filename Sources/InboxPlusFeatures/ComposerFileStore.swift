import Foundation

/// Pictures pasted or dropped into the composer without a file of their own, kept only until they
/// are sent or taken back.
///
/// They are message content, so they get the media cache's privacy: each one in its own `0700`
/// folder, readable only by this user.
public struct ComposerFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// For a session with no profile to keep them in.
    public static func temporary() -> ComposerFileStore {
        ComposerFileStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("InboxPlus-composer-\(UUID().uuidString)", isDirectory: true)
        )
    }

    func write(_ data: Data, named filename: String) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// Deletes a picture this store wrote. Anything else is the user's own file and is left alone.
    func discard(_ fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Nothing staged outlives the app, so whatever is here was left behind by an earlier launch.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
