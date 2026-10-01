import SwiftUI

public enum SidebarSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case inbox, contacts, settings

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .contacts: "Contacts"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray.full.fill"
        case .contacts: "person.2.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct NavigationRailView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        VStack(spacing: 14) {
            // The generated Inbox+ mark is bundled for both packaged and SwiftPM launches.
            Group {
                if let logo = Bundle.module.image(forResource: "InboxPlusLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    Image(systemName: "message.fill")
                        .foregroundStyle(InboxPlusTheme.paper)
                        .background(InboxPlusTheme.ink, in: .rect(cornerRadius: 10))
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityLabel("Inbox+")
            .padding(.bottom, 4)

            ForEach([SidebarSection.inbox, .contacts]) { section in
                railButton(section)
            }
            Spacer()
            railButton(.settings)
        }
        .padding(.vertical, 14)
        .frame(width: 54)
        .background(.quaternary.opacity(0.25))
    }

    private func railButton(_ section: SidebarSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            Image(systemName: section.symbolName)
                .foregroundStyle(isSelected ? AnyShapeStyle(InboxPlusTheme.ink) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? InboxPlusTheme.ink.opacity(0.15) : .clear,
                    in: .rect(cornerRadius: 8)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("rail-\(section.rawValue)")
        .help(section.title)
    }
}
