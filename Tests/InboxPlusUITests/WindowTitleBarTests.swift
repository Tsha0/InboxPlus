import AppKit
import Testing
import InboxPlusFeatures
@testable import InboxPlusUI

@MainActor
@Test func aThemedTitleBarTakesTheBackgroundColorAndClassicGivesTheStandardOneBack() throws {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let titleBar = WindowTitleBar.TitleBarView()
    window.contentView?.addSubview(titleBar)

    let grape = try #require(InboxPlusTheme(.preset(.grapeSoda)).titleBar)
    titleBar.color = grape
    #expect(window.titlebarAppearsTransparent)
    #expect(window.titleVisibility == .hidden)
    #expect(window.backgroundColor == grape)

    titleBar.color = InboxPlusTheme(.standard).titleBar
    #expect(!window.titlebarAppearsTransparent)
    #expect(window.titleVisibility == .visible)
    #expect(window.backgroundColor == .windowBackgroundColor)
}
