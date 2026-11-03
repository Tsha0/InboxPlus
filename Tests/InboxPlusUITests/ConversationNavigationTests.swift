import AppKit
import SwiftUI
import Testing
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
@testable import InboxPlusUI

@MainActor
@Test func leavingAPhotoConversationForSettingsDetachesTheComposerAndPreservesItsDraft() async throws {
    let route = ConversationRoute(accountID: "imessage-local", conversationID: "photo-fixture")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let photo = directory.appendingPathComponent("fixture.png")
    let image = NSImage(size: NSSize(width: 400, height: 300))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 300).fill()
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: photo)
    let messages = (0..<18).map { index in
        Message(
            id: "photo-\(index)", route: route, senderIdentityID: "fixture-contact",
            body: "Fixture photo", timestamp: Date(timeIntervalSince1970: Double(index)),
            deliveryState: .acknowledged, kind: .image,
            attachments: [MessageAttachment(
                id: "image-\(index)", kind: .image, pixelSize: PixelSize(width: 400, height: 300),
                source: MediaHandle(source: photo.absoluteString, mimeType: "image/png")
            )]
        )
    }
    let snapshot = MessagingSnapshot(
        accounts: [.init(id: route.accountID, platform: .iMessage, displayName: "Fixture iMessage")],
        identities: [.init(id: "fixture-contact", accountID: route.accountID, displayName: "Fixture contact")],
        conversations: [.init(id: route.conversationID, accountID: route.accountID, identityID: "fixture-contact",
                              title: "Fixture photos", latestPreview: "Photo", latestActivity: .now, unreadCount: 0)],
        messagesByRoute: [route: messages]
    )
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot))
    try await model.start()
    defer { model.stop() }
    model.openConversation(route)
    model.setDraft("Unsent fixture draft\nSecond line", for: route)
    let suiteName = "InboxPlusNavigationTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let host = NSHostingView(rootView: RootView(model: model, preferences: AppPreferences(defaults: defaults)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }

    for iteration in 0..<10 {
        try await settle(host)
        let composer = try #require(descendants(host).compactMap { $0 as? ComposerTextView }.first)
        #expect(composer.string == "Unsent fixture draft\nSecond line")
        #expect(messages.contains { model.media.state(for: $0.attachments[0]) == .ready(photo) })
        window.makeFirstResponder(composer)
        if iteration == 0 { try capture(host, named: "photo-conversation") }
        try click(NSPoint(x: 27, y: 29), in: window)
        try await settle(host)
        #expect(descendants(host).allSatisfy { !($0 is ComposerTextView) })
        #expect(composer.window == nil)
        #expect(window.firstResponder !== composer)
        #expect(model.draft(for: route) == "Unsent fixture draft\nSecond line")
        if iteration == 0 { try capture(host, named: "settings") }
        try click(NSPoint(x: 27, y: host.bounds.height - 79), in: window)
    }
}

@MainActor
private func settle(_ host: NSView) async throws {
    for _ in 0..<5 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor
private func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}

@MainActor
private func click(_ point: NSPoint, in window: NSWindow) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        window.sendEvent(event)
    }
}

@MainActor
private func capture(_ host: NSView, named name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["INBOXPLUS_NAVIGATION_SCREENSHOTS"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: directory.appendingPathComponent("\(name).png"))
}
