import AppKit
import SwiftUI
import InboxPlusFeatures

/// The colors views paint with: the monochrome Inbox+ look, or the theme chosen in Settings.
struct InboxPlusTheme {
    /// Neutral foreground/background pairs remain legible in either macOS appearance.
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? .white : .black
    })
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? .black : .white
    })

    /// Solid fills: your own message bubbles and unread counts.
    let accent: Color
    /// Text on an accent fill.
    let onAccent: Color
    /// The accent as an icon, outline or faint selection on the window background, darkened or
    /// lightened in each mode until it stands out there.
    let highlight: Color
    let rail: AnyShapeStyle
    /// Selected sections and buttons on the rail.
    let onRail: Color
    let onRailPrimary: AnyShapeStyle
    let onRailSecondary: AnyShapeStyle
    /// Laid over the window background behind the sidebar lists.
    let sidebarWash: Color
    let logo: Color
    let onLogo: Color
    let logoGlow: Color
    /// Nil keeps the standard macOS title bar.
    let titleBar: NSColor?

    static var classic: InboxPlusTheme {
        InboxPlusTheme(
            accent: ink, onAccent: paper, highlight: ink,
            rail: AnyShapeStyle(.quaternary.opacity(0.25)), onRail: ink,
            onRailPrimary: AnyShapeStyle(.primary), onRailSecondary: AnyShapeStyle(.secondary),
            sidebarWash: .clear, logo: .black, onLogo: .white, logoGlow: ink, titleBar: nil
        )
    }

    fileprivate static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension InboxPlusTheme {
    init(_ theme: AppTheme) {
        self = theme.palette.map(InboxPlusTheme.init(palette:)) ?? .classic
    }

    private init(palette: ThemePalette) {
        let onRail = Color(palette.background.legibleText)
        self.init(
            accent: Color(palette.accent),
            onAccent: Color(palette.accent.legibleText),
            highlight: Color(nsColor: NSColor(name: nil) { appearance in
                // The window backgrounds of each mode, where the highlight has to show.
                let surface = Self.isDark(appearance) ? ThemeColor(0x323232) : ThemeColor(0xECECEC)
                return NSColor(palette.accent.readable(on: surface, minimumContrast: 3))
            }),
            rail: AnyShapeStyle(Color(palette.background)),
            onRail: onRail,
            onRailPrimary: AnyShapeStyle(onRail),
            onRailSecondary: AnyShapeStyle(onRail.opacity(0.7)),
            sidebarWash: Color(nsColor: NSColor(name: nil) { appearance in
                // A pale background washes a dark window murky long before a deep one shows.
                let darkModeOpacity = palette.background.legibleText == .black ? 0.1 : 0.22
                return NSColor(palette.background).withAlphaComponent(Self.isDark(appearance) ? darkModeOpacity : 0.12)
            }),
            logo: Color(palette.logo),
            onLogo: Color(palette.logo.legibleText),
            logoGlow: Color(palette.logo),
            titleBar: NSColor(palette.background)
        )
    }
}

/// Paints the window's title bar in the theme's background, continuing the rail across the top.
struct WindowTitleBar: NSViewRepresentable {
    let color: NSColor?

    func makeNSView(context: Context) -> TitleBarView { TitleBarView() }

    func updateNSView(_ view: TitleBarView, context: Context) {
        view.color = color
    }

    final class TitleBarView: NSView {
        var color: NSColor? {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// A transparent title bar shows the window's own background color. The title text follows
        /// the light or dark mode rather than the theme, so it is hidden where it could clash.
        private func apply() {
            guard let window else { return }
            window.titlebarAppearsTransparent = color != nil
            window.titleVisibility = color == nil ? .visible : .hidden
            window.backgroundColor = color ?? .windowBackgroundColor
        }
    }
}

extension EnvironmentValues {
    @Entry var inboxPlusTheme: InboxPlusTheme = .classic
}

extension AppearanceMode {
    /// Nil follows macOS.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension Color {
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

extension NSColor {
    convenience init(_ color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

extension ThemeColor {
    /// Nil for a color with no sRGB equivalent, such as a pattern.
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
