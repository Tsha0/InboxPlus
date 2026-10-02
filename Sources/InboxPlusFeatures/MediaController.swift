import Foundation
import Observation
import InboxPlusCore
import InboxPlusGateway

/// Loads media only when a transcript asks for it and retains the resulting local URLs.
@MainActor
@Observable
public final class MediaController {
    public enum State: Equatable {
        case idle
        case loading
        case ready(URL)
        case failed(String)
        case paused(String)
    }

    private struct AttachmentKey: Hashable {
        let accountID: String
        let attachmentID: String
    }

    private var loader: MediaLoader?
    @ObservationIgnored private var loaderGeneration: UInt64 = 0
    @ObservationIgnored private var loadedSourceByAttachmentID: [AttachmentKey: String] = [:]
    private var states: [AttachmentKey: State] = [:]
    private struct LoadTask {
        let id: UUID
        let task: Task<Void, Never>
    }
    @ObservationIgnored private var tasks: [AttachmentKey: LoadTask] = [:]
    @ObservationIgnored private var generationsByAccount: [String: UInt64] = [:]
    @ObservationIgnored private var purgedAccountIDs: Set<String> = []
    @ObservationIgnored private var purgeTasks: [String: Task<Void, Never>] = [:]
    public private(set) var storageWarning: String?

    public init(loader: MediaLoader? = nil) {
        self.loader = loader
    }

    public func attach(loader: MediaLoader) {
        for (attachmentID, load) in tasks {
            load.task.cancel()
            if states[attachmentID] == .loading { states[attachmentID] = nil }
        }
        tasks.removeAll()
        self.loader = loader
        loaderGeneration &+= 1
        let generation = loaderGeneration
        Task { [weak self] in
            let warning = await loader.storageDecision().warning
            guard let self, loaderGeneration == generation else { return }
            storageWarning = warning
        }
    }

    public func state(for attachment: MessageAttachment, accountID: String) -> State {
        states[AttachmentKey(accountID: accountID, attachmentID: attachment.id)] ?? .idle
    }

    public func load(_ attachment: MessageAttachment, accountID: String, messageID: String,
                     useThumbnail: Bool = true) {
        let key = AttachmentKey(accountID: accountID, attachmentID: attachment.id)
        guard !purgedAccountIDs.contains(accountID), let loader else { return }
        let handle: MediaHandle?
        switch attachment.kind {
        case .image, .gallery: handle = useThumbnail ? attachment.thumbnail ?? attachment.source : attachment.source
        default: handle = attachment.source
        }
        guard let handle else { return }
        switch state(for: attachment, accountID: accountID) {
        case .idle, .failed: break
        case .loading, .ready, .paused: return
        }

        let generation = generationsByAccount[accountID, default: 0]
        let pendingPurge = purgeTasks[accountID]
        let loaderGeneration = loaderGeneration
        states[key] = .loading
        let loadID = UUID()
        let task = Task { [weak self] in
            defer {
                if self?.tasks[key]?.id == loadID { self?.tasks[key] = nil }
            }
            let context = MediaCacheContext(accountID: accountID, messageID: messageID,
                                            deepLink: attachment.deepLink)
            do {
                await pendingPurge?.value
                try Task.checkCancellation()
                let warning = await loader.storageDecision().warning
                let url: URL
                var loadedSource = handle.source
                do {
                    url = try await loader.file(for: handle, context: context)
                } catch is CancellationError {
                    throw CancellationError()
                } catch MediaLoadError.pausedForDiskSpace {
                    throw MediaLoadError.pausedForDiskSpace
                } catch {
                    guard let original = attachment.source, original.source != handle.source else { throw error }
                    url = try await loader.file(for: original, context: context)
                    loadedSource = original.source
                }
                guard !Task.isCancelled, let self,
                      generationsByAccount[accountID, default: 0] == generation,
                      self.loaderGeneration == loaderGeneration,
                      tasks[key]?.id == loadID else { return }
                storageWarning = warning
                loadedSourceByAttachmentID[key] = loadedSource
                states[key] = .ready(url)
            } catch MediaLoadError.pausedForDiskSpace {
                let decision = await loader.storageDecision()
                guard !Task.isCancelled, let self,
                      generationsByAccount[accountID, default: 0] == generation,
                      self.loaderGeneration == loaderGeneration,
                      tasks[key]?.id == loadID else { return }
                storageWarning = decision.warning
                states[key] = .paused(
                    decision.warning ?? "Downloads are paused because your Mac is low on disk space."
                )
            } catch {
                guard !Task.isCancelled, let self,
                      generationsByAccount[accountID, default: 0] == generation,
                      self.loaderGeneration == loaderGeneration,
                      tasks[key]?.id == loadID else { return }
                states[key] = .failed(error.localizedDescription)
            }
        }
        tasks[key] = LoadTask(id: loadID, task: task)
    }

    public func retry(_ attachment: MessageAttachment, accountID: String, messageID: String) {
        let key = AttachmentKey(accountID: accountID, attachmentID: attachment.id)
        tasks.removeValue(forKey: key)?.task.cancel()
        states[key] = .idle
        load(attachment, accountID: accountID, messageID: messageID)
    }

    /// A bridge thumbnail can download successfully yet be undecodable; try the original once.
    @discardableResult
    public func retryOriginal(_ attachment: MessageAttachment, accountID: String, messageID: String) -> Bool {
        let key = AttachmentKey(accountID: accountID, attachmentID: attachment.id)
        guard let thumbnail = attachment.thumbnail, let original = attachment.source,
              original.source != thumbnail.source,
              loadedSourceByAttachmentID[key] == thumbnail.source else { return false }
        states[key] = .idle
        load(attachment, accountID: accountID, messageID: messageID, useThumbnail: false)
        return true
    }

    /// Cancels pending UI work immediately; the loader also prevents late downloads recreating files.
    @discardableResult
    public func purge(accountID: String) -> Task<Void, Never> {
        purgedAccountIDs.insert(accountID)
        generationsByAccount[accountID, default: 0] &+= 1
        for key in states.keys.filter({ $0.accountID == accountID }) {
            tasks.removeValue(forKey: key)?.task.cancel()
            states[key] = nil
            loadedSourceByAttachmentID[key] = nil
        }
        let loader = loader
        let previousPurge = purgeTasks[accountID]
        let task = Task { [weak self] in
            await previousPurge?.value
            do { try await loader?.purge(accountID: accountID) }
            catch { self?.storageWarning = "Cached media could not be erased: \(error.localizedDescription)" }
        }
        purgeTasks[accountID] = task
        return task
    }

    public func allowDownloads(accountID: String) {
        purgedAccountIDs.remove(accountID)
    }

    isolated deinit {
        tasks.values.forEach { $0.task.cancel() }
    }
}
