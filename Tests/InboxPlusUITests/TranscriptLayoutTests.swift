import AppKit
import SwiftUI
import Testing
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusTestSupport
@testable import InboxPlusUI

private struct DelayedPhotoFetcher: RemoteMediaFetching {
    let data: Data
    func fetch(_ handle: MediaHandle) async throws -> Data {
        try await Task.sleep(for: .milliseconds(250))
        return data
    }
}

private struct PhotoFreeSpace: FreeSpaceReporting {
    func freeBytes() -> Int? { 100 * 1024 * 1024 * 1024 }
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [true, false], [true, false])
func photoTranscriptKeepsItsFocusAfterMediaLoads(reportsDimensions: Bool, opensSearchResult: Bool) async throws {
    let route = Fixtures.instagramRoute
    let photoSize = opensSearchResult ? PixelSize(width: 800, height: 400) : PixelSize(width: 400, height: 800)
    var snapshot = Fixtures.snapshot
    snapshot.messagesByRoute[route] = (0..<18).map { index -> Message in
        let attachment = MessageAttachment(
            id: "image-\(index)", kind: .image,
            pixelSize: reportsDimensions ? photoSize : nil,
            source: MediaHandle(source: "mxc://fixture/image-\(index)", mimeType: "image/png")
        )
        return Message(
            id: "photo-\(index)", route: route, senderIdentityID: "maya-instagram-identity",
            body: index == 17 ? "Newest fixture message" : "Photo", timestamp: Date(timeIntervalSince1970: Double(index)),
            deliveryState: .acknowledged, kind: index < 16 ? .image : .text,
            attachments: index < 16 ? [attachment] : []
        )
    }
    let image = NSImage(size: NSSize(width: photoSize.width, height: photoSize.height))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptLayout-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let media = MediaController(loader: MediaLoader(
        cache: try MediaCache(directory: directory),
        fetcher: DelayedPhotoFetcher(data: data), freeSpace: PhotoFreeSpace()
    ))
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot), media: media)
    try await model.start()
    defer { model.stop() }
    if opensSearchResult {
        model.openMessage(MessageReference(route: route, messageID: "photo-9"))
    }
    let host = NSHostingView(rootView: ConversationView(model: model, route: route))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    let attachmentIndex = opensSearchResult ? 9 : 15
    let attachment = try #require(snapshot.messagesByRoute[route]?[attachmentIndex].attachments.first)
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while ContinuousClock.now < deadline {
        host.layoutSubtreeIfNeeded()
        if case .ready = media.state(for: attachment) { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    for _ in 0..<3 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
    let table = try #require(descendants(host).compactMap { $0 as? NSTableView }.first)
    let visible = table.rows(in: table.visibleRect)
    guard case .ready = media.state(for: attachment) else {
        Issue.record("The visible fixture photo must finish loading before its scroll position is checked")
        return
    }
    if opensSearchResult {
        #expect(abs(table.rect(ofRow: 10).midY - table.visibleRect.midY) < 2)
    } else {
        #expect(NSMaxRange(visible) == table.numberOfRows)
    }
    if let directory = ProcessInfo.processInfo.environment["INBOXPLUS_TRANSCRIPT_SCREENSHOTS"] {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("photo-dimensions-\(reportsDimensions)-search-\(opensSearchResult).png"))
    }
}

@MainActor
private func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}
