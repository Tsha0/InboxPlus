import SwiftUI

struct NavigationRailView: View {
    var body: some View {
        VStack(spacing: 18) {
            Text("P")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black, in: .rect(cornerRadius: 10))
                .accessibilityLabel("Pallo")
            railButton("tray.full.fill", label: "Inbox", isSelected: true)
            railButton("magnifyingglass", label: "Search")
            railButton("person.2.fill", label: "Contacts")
            Spacer()
            railButton("gearshape.fill", label: "Settings")
        }
        .padding(.vertical, 14)
        .frame(width: 54)
    }

    private func railButton(_ symbol: String, label: String, isSelected: Bool = false) -> some View {
        Button(action: {}) {
            Image(systemName: symbol)
                .frame(width: 30, height: 30)
                .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
