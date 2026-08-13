import SwiftUI
import PalloCore
import PalloFeatures

struct AccountsListView: View {
    let accounts: [ConnectedAccount]
    let health: ServiceHealth
    let isConnected: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.title2.bold())
                .padding(.horizontal)

            HStack(spacing: 8) {
                Image(systemName: health.symbolName)
                    .foregroundStyle(health == .healthy ? Color.green : .orange)
                Text(health.menuBarTitle)
                    .font(.callout)
            }
            .padding(.horizontal)

            Text("Connected accounts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            List(accounts) { account in
                HStack(spacing: 10) {
                    PlatformBadge(platform: account.platform)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.platform.accessibilityLabel)
                            .fontWeight(.semibold)
                        Text(account.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Circle()
                        .fill(isConnected(account.id) ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(isConnected(account.id) ? "Connected" : "Disconnected")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account-row-\(account.id)")
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
        .accessibilityIdentifier("pallo-settings")
    }
}
