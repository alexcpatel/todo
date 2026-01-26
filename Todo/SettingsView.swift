import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section {
                LabeledContent("Sync Status", value: store.syncStatus)

                if store.isUsingiCloud {
                    Text("Data syncs automatically via iCloud Drive")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("iCloud not available. Data stored locally.")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Button("Refresh") {
                    store.load()
                    store.updateSyncStatus()
                }
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}
