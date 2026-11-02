import SwiftUI
import InboxPlusCore

/// The emoji a reaction can be chosen from beyond the quick ones.
enum EmojiCatalog {
    struct Category: Identifiable {
        let name: String
        let emoji: [String]
        var id: String { name }

        init(_ name: String, _ emoji: String) {
            self.name = name
            self.emoji = emoji.split(separator: " ").map(String.init)
        }
    }

    /// The usual reactions, to browse. Everything else is found by searching.
    static let categories = [
        Category("Smileys", """
        😀 😃 😄 😁 😆 😅 🤣 😂 🙂 😉 😊 😇 🥰 😍 🤩 😘 😋 😛 😜 🤪 😝 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 \
        😏 😒 🙄 😬 😌 😔 😪 🤤 😴 😷 🤒 🤢 🤮 🥵 🥶 🥴 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 \
        😳 🥺 🥹 😦 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 💀 💩 🤡 👻 👽 🤖
        """),
        Category("Gestures", """
        👍 👎 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💪 \
        🫶 👀 🧠 🙈 🙉 🙊
        """),
        Category("Hearts", "❤️ 🩷 🧡 💛 💚 💙 🩵 💜 🖤 🩶 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟"),
        Category("Celebration", """
        🎉 🎊 🎈 🎂 🎁 🏆 🥇 🔥 ✨ ⭐ 🌟 💯 ✅ ❌ ❓ ❗ 💥 💫 💤 💬 👑 💎 💰 🚀
        """),
        Category("Animals and nature", """
        🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🦄 🐝 🦋 🐢 🐍 🐙 🐳 🐬 🌸 🌹 🌻 \
        🌈 ☀️ 🌙 ⚡ ❄️ 🌊
        """),
        Category("Food and drink", """
        🍎 🍓 🍑 🍒 🍉 🍌 🥑 🍕 🍔 🍟 🌮 🍣 🍜 🍩 🍪 🍰 🍫 🍿 ☕ 🍵 🍺 🍻 🥂 🍷 🍸
        """),
    ]

    /// Every emoji that is one character, named so it can be searched, with the usual reactions
    /// first so they lead the results. Newer ones than Unicode 15.1 are left out because macOS 15.0
    /// draws them as empty boxes.
    static let all: [(emoji: String, name: String)] = {
        let ranges: [ClosedRange<UInt32>] = [0x2000...0x32FF, 0x1F000...0x1FAFF]
        let named: [(emoji: String, name: String)] = ranges.joined().compactMap { value in
            guard let scalar = Unicode.Scalar(value) else { return nil }
            let properties = scalar.properties
            guard properties.isEmoji, !properties.isEmojiModifier, !(0x1F1E6...0x1F1FF).contains(value),
                  let age = properties.age, age <= (15, 1),
                  let name = properties.name else { return nil }
            // Without the variation selector, a character such as ❤ is drawn as a black glyph.
            let emoji = properties.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
            return (emoji, name.lowercased())
        }
        let browsed = categories.flatMap(\.emoji)
        let browsedSet = Set(browsed)
        let byEmoji = Dictionary(named.map { ($0.emoji, $0) }, uniquingKeysWith: { first, _ in first })
        return browsed.compactMap { byEmoji[$0] } + named.filter { !browsedSet.contains($0.emoji) }
    }()

    /// Matches every word of the query against an emoji's Unicode name, such as "face with tears
    /// of joy" for 😂.
    static func search(_ query: String) -> [String] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return all.filter { entry in words.allSatisfy { entry.name.contains($0) } }.map(\.emoji)
    }
}

/// Opened from a message's reaction button: the quick reactions in one row, and every other emoji
/// behind **+**. Choosing one that is already yours takes it back, as the pills under a bubble do.
struct ReactionPicker: View {
    private static let cellSize: CGFloat = 32
    private static let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: 2), count: 7)

    let reactions: [MessageReaction]
    let choose: (String) -> Void
    @State private var showsAll = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var results: [String] {
        EmojiCatalog.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(TranscriptPresentation.quickReactions, id: \.self) { key in
                    emojiButton(key)
                }
                Button {
                    showsAll.toggle()
                } label: {
                    Image(systemName: showsAll ? "chevron.up" : "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: Self.cellSize, height: Self.cellSize)
                        .background(.quaternary, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(showsAll ? "Fewer emoji" : "More emoji")
                .accessibilityLabel(showsAll ? "Fewer emoji" : "More emoji")
                .accessibilityIdentifier("more-reactions")
            }
            if showsAll {
                TextField("Search emoji", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { choose(first) } }
                    .onAppear { searchFocused = true }
                    .accessibilityIdentifier("search-reactions")
                ScrollView {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 2) {
                        if isSearching {
                            ForEach(results, id: \.self, content: emojiButton)
                        } else {
                            ForEach(EmojiCatalog.categories) { category in
                                Section {
                                    ForEach(category.emoji, id: \.self, content: emojiButton)
                                } header: {
                                    Text(category.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 6)
                                        .accessibilityAddTraits(.isHeader)
                                }
                            }
                        }
                    }
                }
                .frame(height: 230)
                .overlay {
                    if isSearching, results.isEmpty {
                        Text("No emoji found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("reaction-picker")
    }

    private func emojiButton(_ key: String) -> some View {
        EmojiButton(
            key: key,
            size: Self.cellSize,
            isMine: reactions.contains { $0.key == key && $0.includesMe },
            choose: choose
        )
    }
}

private struct EmojiButton: View {
    let key: String
    let size: CGFloat
    let isMine: Bool
    let choose: (String) -> Void
    @State private var isHovering = false

    private var background: AnyShapeStyle {
        if isMine { return AnyShapeStyle(InboxPlusTheme.ink.opacity(0.18)) }
        return isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }

    var body: some View {
        Button { choose(key) } label: {
            Text(key)
                .font(.system(size: size * 0.65))
                .frame(width: size, height: size)
                .background(background, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isMine ? "Remove your \(key)" : "React with \(key)")
        .accessibilityAddTraits(isMine ? .isSelected : [])
    }
}
