import SwiftUI

/// A small, replayable brand moment anchored to the logo rather than a modal over the inbox.
struct InboxPlusLogoButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Group {
                if let logo = Bundle.module.image(forResource: "InboxPlusLogo") {
                    Image(nsImage: logo).resizable()
                } else {
                    Image(systemName: "asterisk")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(.rect(cornerRadius: 8))
            .scaleEffect(isHovering && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Inbox+ logo")
        .accessibilityHint("Play the logo animation")
        .accessibilityIdentifier("rail-logo")
        .help("Watch x + become Inbox+")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            LogoMergePopover()
        }
    }
}

private struct LogoMergePopover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var isPlaying = true
    private let stackedLogo = Bundle.module.image(forResource: "InboxPlusLogoStacked")
    private let finalLogo = Bundle.module.image(forResource: "InboxPlusLogo")

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(paused: !isPlaying)) { context in
                LogoMergeArtwork(
                    elapsed: isPlaying ? max(0, context.date.timeIntervalSince(startedAt)) : LogoMergeArtwork.duration,
                    reduceMotion: reduceMotion,
                    stackedLogo: stackedLogo,
                    finalLogo: finalLogo
                )
            }
            .frame(width: 220, height: 220)

            HStack {
                Text("Inbox+")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Button { replay() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.1), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay logo animation")
                .accessibilityIdentifier("logo-replay")
                .help("Replay")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inbox+ logo animation: x and plus merge into an asterisk")
        .onAppear { replay() }
        .onChange(of: reduceMotion) { replay() }
        .task(id: startedAt) {
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.45 : LogoMergeArtwork.duration))
                isPlaying = false
            } catch {
                // Replay or dismissal cancels the previous playback without changing the new one.
            }
        }
    }

    private func replay() {
        isPlaying = true
        startedAt = Date()
    }
}
