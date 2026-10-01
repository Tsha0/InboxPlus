import AppKit
import SwiftUI

/// Neutral foreground/background pairs remain legible in either macOS appearance.
enum InboxPlusTheme {
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    })
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })
}
