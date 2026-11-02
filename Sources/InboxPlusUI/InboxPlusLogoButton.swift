import SwiftUI

/// A brief spin and glow on the navigation logo, within the main window.
struct InboxPlusLogoButton: View {
    /// Plays the animation whenever it changes, as a click does.
    var celebration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.inboxPlusTheme) private var theme
    @State private var isHovering = false
    @State private var rotation = 0.0
    @State private var glow = 0.0
    @State private var activation: Date?

    var body: some View {
        Button(action: play) {
            Group {
                if let logo = UIResources.bundle?.image(forResource: "InboxPlusLogo") {
                    // The artwork is a white asterisk on black, so its brightness cuts the glyph
                    // out of the theme's logo color.
                    theme.onLogo
                        .mask { Image(nsImage: logo).resizable().luminanceToAlpha() }
                        .rotationEffect(.degrees(rotation))
                } else {
                    Image(systemName: "asterisk")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(theme.onLogo)
                        .rotationEffect(.degrees(rotation))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 32, height: 32)
            .background(theme.logo)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.onLogo.opacity(glow * 0.45), lineWidth: 1)
            }
            .shadow(color: theme.logoGlow.opacity(glow * 0.4), radius: glow * 7)
            .scaleEffect(reduceMotion ? 1 : (isHovering ? 1.04 : 1) + glow * 0.04)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Inbox+ logo")
        .accessibilityHint(reduceMotion ? "Glow the logo" : "Spin and glow the logo")
        .accessibilityIdentifier("rail-logo")
        .help("Animate the Inbox+ logo")
        .onChange(of: reduceMotion) {
            if reduceMotion { withAnimation(nil) { rotation = 0 } }
        }
        .onChange(of: celebration) { play() }
        .task(id: activation) {
            guard activation != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeOut(duration: 0.85)) { glow = 0 }
            } catch {
                // A new click cancels the old fade; the latest click owns the glow.
            }
        }
    }

    private func play() {
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.9)) { rotation += 360 }
        }
        withAnimation(.easeOut(duration: 0.13)) { glow = 1 }
        activation = Date()
    }
}
