import SwiftUI
import InboxPlusFeatures

/// Settings → Appearance: ready-made themes, your own colors, and light or dark mode.
struct AppearanceSection: View {
    @Bindable var preferences: AppPreferences
    /// Called for a theme the user picked outright, not for every step of dragging a color.
    var onThemePicked: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 12)]

    var body: some View {
        Section {
            Picker("Appearance", selection: $preferences.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearance-mode")

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ThemePreset.allCases) { preset in
                    swatch(preset.name, id: preset.id, theme: .preset(preset))
                }
                if let custom = preferences.customPalette {
                    swatch("Custom", id: "custom", theme: .custom(custom))
                }
            }
            .padding(.vertical, 4)

            ColorPicker("Background", selection: color(\.background), supportsOpacity: false)
            ColorPicker("Accent", selection: color(\.accent), supportsOpacity: false)
            ColorPicker("Logo", selection: color(\.logo), supportsOpacity: false)

            HStack {
                Button("Surprise Me", systemImage: "dice") {
                    pick(.custom(.surprise(hue: .random(in: 0..<1), lightBackground: .random())))
                }
                .accessibilityIdentifier("theme-surprise")
                Spacer()
                Button("Reset to Classic") { pick(.standard) }
                    .disabled(preferences.theme == .standard)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Pick a theme or mix your own. Text on colored backgrounds turns light or dark to stay readable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func swatch(_ name: String, id: String, theme: AppTheme) -> some View {
        ThemeSwatch(name: name, theme: InboxPlusTheme(theme), isSelected: preferences.theme == theme) {
            pick(theme)
        }
        .accessibilityIdentifier("theme-\(id)")
    }

    private var editablePalette: ThemePalette {
        preferences.theme.palette ?? .monochrome(dark: colorScheme == .dark)
    }

    /// Changing any color turns the current theme into a custom one.
    private func color(_ role: WritableKeyPath<ThemePalette, ThemeColor>) -> Binding<Color> {
        Binding(
            get: { Color(editablePalette[keyPath: role]) },
            set: { color in
                var palette = editablePalette
                guard let chosen = ThemeColor(color), chosen != palette[keyPath: role] else { return }
                palette[keyPath: role] = chosen
                preferences.theme = .custom(palette)
            }
        )
    }

    private func pick(_ theme: AppTheme) {
        preferences.theme = theme
        onThemePicked()
    }
}

/// A theme drawn as a tiny window: its rail and logo beside a conversation.
private struct ThemeSwatch: View {
    let name: String
    let theme: InboxPlusTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.inboxPlusTheme) private var current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 0) {
                    VStack {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(theme.logo)
                            .frame(width: 11, height: 11)
                            .overlay {
                                Image(systemName: "asterisk")
                                    .font(.system(size: 6, weight: .heavy))
                                    .foregroundStyle(theme.onLogo)
                            }
                        Spacer()
                    }
                    .padding(.top, 6)
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .background(theme.rail)
                    VStack(spacing: 4) {
                        Capsule().fill(.quaternary)
                            .frame(width: 30, height: 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Capsule().fill(theme.accent)
                            .frame(width: 34, height: 7)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Capsule().fill(.quaternary)
                            .frame(width: 22, height: 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .frame(maxHeight: .infinity)
                    .background(theme.sidebarWash)
                    .background(.background)
                }
                .frame(height: 52)
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? AnyShapeStyle(current.highlight) : AnyShapeStyle(.quaternary),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel("\(name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
